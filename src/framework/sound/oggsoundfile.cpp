/*
 * Copyright (c) 2010-2026 OTClient <https://github.com/edubart/otclient>
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#include "oggsoundfile.h"

#include "framework/core/filestream.h"

bool OggSoundFile::prepareOgg()
{
    constexpr ov_callbacks callbacks = { cb_read, cb_seek, cb_close, cb_tell };
    ov_open_callbacks(m_file.get(), &m_vorbisFile, nullptr, 0, callbacks);

    const vorbis_info* vi = ov_info(&m_vorbisFile, -1);
    if (!vi) {
        g_logger.error("Ogg file not supported: {}", m_file->name());
        return false;
    }

    m_channels = vi->channels;
    m_rate = vi->rate;
    m_bps = 16;
    m_size = ov_pcm_total(&m_vorbisFile, -1) * (m_bps / 8) * m_channels;

    return true;
}

void OggSoundFile::preloadPCM(int maxBytes)
{
    if (!m_preloadedPCM.empty())
        return;

    m_preloadedPCM.resize(maxBytes);
    int totalRead = 0;
    int section = 0;
    while (totalRead < maxBytes) {
        const long n = ov_read(&m_vorbisFile, m_preloadedPCM.data() + totalRead, maxBytes - totalRead, 0, 2, 1, &section);
        if (n <= 0)
            break;
        totalRead += n;
    }
    m_preloadedPCM.resize(totalRead);
    m_preloadedOffset = 0;
    // OGG decoder is now positioned right after the preloaded data;
    // subsequent read() calls will continue from there seamlessly.
}

int OggSoundFile::read(void* buffer, int bufferSize)
{
    auto* bytesBuffer = reinterpret_cast<char*>(buffer);
    int totalBytesRead = 0;

    // Serve from preloaded PCM cache first (decoded on async thread).
    if (m_preloadedOffset < static_cast<int>(m_preloadedPCM.size())) {
        const int available = static_cast<int>(m_preloadedPCM.size()) - m_preloadedOffset;
        const int toRead = std::min(bufferSize, available);
        std::memcpy(bytesBuffer, m_preloadedPCM.data() + m_preloadedOffset, toRead);
        m_preloadedOffset += toRead;
        totalBytesRead += toRead;
        bytesBuffer += toRead;
        bufferSize -= toRead;
    }

    // OGG decoder picks up exactly where preloadPCM() left off.
    int section = 0;
    while (bufferSize > 0) {
        const long n = ov_read(&m_vorbisFile, bytesBuffer, bufferSize, 0, 2, 1, &section);
        if (n <= 0)
            break;
        bufferSize -= n;
        bytesBuffer += n;
        totalBytesRead += n;
    }

    return totalBytesRead;
}

int OggSoundFile::cb_seek(void* source, const ogg_int64_t offset, const int whence)
{
    auto* const file = static_cast<FileStream*>(source);
    switch (whence) {
        case SEEK_SET:
            file->seek(offset);
            return 0;
        case SEEK_CUR:
            file->seek(file->tell() + offset);
            return 0;
        case SEEK_END:
            file->seek(file->size() + offset);
            return 0;
    }
    return -1;
}

int OggSoundFile::cb_close(void* source) {
    static_cast<FileStream*>(source)->close();
    return 0;
}

void OggSoundFile::reset()
{
    // Discard the preloaded cache on loop so subsequent reads go straight to the
    // OGG decoder, which is now rewound to position 0. The first-play stall
    // benefit is a one-shot; looping refills are small (STREAM_FRAGMENT_SIZE each).
    m_preloadedPCM.clear();
    m_preloadedOffset = 0;
    ov_pcm_seek(&m_vorbisFile, 0);
}
long OggSoundFile::cb_tell(void* source) { return static_cast<FileStream*>(source)->tell(); }
size_t OggSoundFile::cb_read(void* ptr, const size_t size, const size_t nmemb, void* source) { return static_cast<FileStream*>(source)->read(ptr, size, nmemb); }