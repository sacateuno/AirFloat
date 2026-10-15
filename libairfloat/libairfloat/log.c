//
//  log.c
//  AirFloat
//
//  Copyright (c) 2013, Kristian Trenskow All rights reserved.
//
//  Redistribution and use in source and binary forms, with or
//  without modification, are permitted provided that the following
//  conditions are met:
//
//  Redistributions of source code must retain the above copyright
//  notice, this list of conditions and the following disclaimer.
//  Redistributions in binary form must reproduce the above
//  copyright notice, this list of conditions and the following
//  disclaimer in the documentation and/or other materials provided
//  with the distribution. THIS SOFTWARE IS PROVIDED BY THE
//  COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
//  IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
//  PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER
//  OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
//  SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
//  LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS
//  OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
//  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
//  STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
//  ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
//  ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#include <stdarg.h>
#include <stdbool.h>
#include <string.h>
#include <stdio.h>
#include <assert.h>
#include <time.h>
#include <pthread.h>
#include <sys/time.h>
#include <sys/stat.h>

#include "log.h"

#define LOG_MAX_BYTES (8 * 1024 * 1024)

#if defined(LOG_SERVER)
static volatile bool _log_enabled = true;
#else
static volatile bool _log_enabled = false;
#endif

static pthread_mutex_t _log_lock = PTHREAD_MUTEX_INITIALIZER;
static char _log_path[512] = "/var/tmp/airfloat.log";
static FILE* _log_file = NULL;
static long _log_bytes = 0;

static void _log_close_locked(void) {
    if (_log_file != NULL) {
        fclose(_log_file);
        _log_file = NULL;
    }
    _log_bytes = 0;
}

static FILE* _log_open_locked(void) {
    if (_log_file == NULL) {
        _log_file = fopen(_log_path, "a");
        if (_log_file != NULL) {
            fseek(_log_file, 0, SEEK_END);
            _log_bytes = ftell(_log_file);
        }
    }
    return _log_file;
}

static void _log_trim_locked(void) {
    if (_log_bytes > LOG_MAX_BYTES) {
        _log_close_locked();
        _log_file = fopen(_log_path, "w");
    }
}

static int _log_timestamp_locked(FILE* f) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    struct tm tm;
    time_t sec = tv.tv_sec;
    localtime_r(&sec, &tm);
    return fprintf(f, "[%02d:%02d:%02d.%03d] ", tm.tm_hour, tm.tm_min, tm.tm_sec, (int)(tv.tv_usec / 1000));
}

void log_set_enabled(bool enabled) {
    pthread_mutex_lock(&_log_lock);
    _log_enabled = enabled;
    if (!enabled)
        _log_close_locked();
    pthread_mutex_unlock(&_log_lock);
}

bool log_is_enabled(void) {
    return _log_enabled;
}

void log_set_file_path(const char* path) {
    if (path == NULL || strlen(path) == 0 || strlen(path) >= sizeof(_log_path))
        return;
    pthread_mutex_lock(&_log_lock);
    _log_close_locked();
    strcpy(_log_path, path);
    pthread_mutex_unlock(&_log_lock);
}

void log_clear(void) {
    pthread_mutex_lock(&_log_lock);
    _log_close_locked();
    FILE* f = fopen(_log_path, "w");
    if (f != NULL)
        fclose(f);
    pthread_mutex_unlock(&_log_lock);
}

long log_file_size(void) {
    struct stat st;
    if (stat(_log_path, &st) != 0)
        return 0;
    return (long)st.st_size;
}

void log_message(int level, const char* message, ...) {
    
    if (!_log_enabled || message == NULL)
        return;
    
#if !defined(LOG_HTTP)
    if (level == LOG_COMMUNICATION)
        return;
#endif
    
    va_list args;
    va_start(args, message);
    
    pthread_mutex_lock(&_log_lock);
    
    FILE* lf = _log_open_locked();
    if (lf != NULL) {
        int written = _log_timestamp_locked(lf);
        int body = vfprintf(lf, message, args);
        fputc('\n', lf);
        fflush(lf);
        if (written > 0) _log_bytes += written;
        if (body > 0) _log_bytes += body;
        _log_bytes += 1;
        _log_trim_locked();
    }
    
    pthread_mutex_unlock(&_log_lock);
    
    va_end(args);
    
}

void log_data(int level, const void* data, size_t data_size) {
    
    if (!_log_enabled || data == NULL || data_size == 0)
        return;
    
#if !defined(LOG_HTTP)
    if (level == LOG_COMMUNICATION)
        return;
#endif
    
    pthread_mutex_lock(&_log_lock);
    
    FILE* lf = _log_open_locked();
    if (lf != NULL) {
        fwrite(data, 1, data_size, lf);
        fputc('\n', lf);
        fflush(lf);
        _log_bytes += (long)data_size + 1;
        _log_trim_locked();
    }
    
    pthread_mutex_unlock(&_log_lock);
    
}
