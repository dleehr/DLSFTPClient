//
//  DLSFTPUploadRequest.m
//  DLSFTPClient
//
//  Created by Dan Leehr on 3/8/13.
//  Copyright (c) 2013 Dan Leehr. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//
//  Redistributions of source code must retain the above copyright notice,
//  this list of conditions and the following disclaimer.
//
//  Redistributions in binary form must reproduce the above copyright
//  notice, this list of conditions and the following disclaimer in the
//  documentation and/or other materials provided with the distribution.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
// IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
// PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
// TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
// PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
// LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
// NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//

#import "DLSFTPUploadRequest.h"
#import "DLSFTPConnection.h"
#import "DLSFTPFile.h"
#import "NSDictionary+SFTPFileAttributes.h"

static const size_t cBufferSize = 8192;

@interface DLSFTPUploadRequest ()

@property (nonatomic, copy) DLSFTPClientProgressBlock progressBlock;
@property (nonatomic, copy) NSString *remotePath;
@property (nonatomic, copy) NSString *localPath;
@property (nonatomic, strong) NSDate *startTime;
@property (nonatomic, strong) NSDate *finishTime;
@property (nonatomic, strong) DLSFTPFile *uploadedFile;
@property (nonatomic) BOOL shouldResume;

@property (nonatomic) int sftp_result;
@property (nonatomic) int read_error;

@property (nonatomic, assign) LIBSSH2_SFTP_HANDLE *handle;

@end

@implementation DLSFTPUploadRequest

- (id)initWithRemotePath:(NSString *)remotePath
               localPath:(NSString *)localPath
            successBlock:(DLSFTPClientFileTransferSuccessBlock)successBlock
            failureBlock:(DLSFTPClientFailureBlock)failureBlock
           progressBlock:(DLSFTPClientProgressBlock)progressBlock {
    self = [super init];
    if (self) {
        self.remotePath = remotePath;
        self.localPath = localPath;
        self.successBlock = successBlock;
        self.failureBlock = failureBlock;
        self.progressBlock = progressBlock;
    }
    return self;
}

- (BOOL)openFileHandle {
    LIBSSH2_SESSION *session = [self.connection session];
    LIBSSH2_SFTP *sftp = [self.connection sftp];
    int socketFD = [self.connection socket];
    LIBSSH2_SFTP_HANDLE *handle = NULL;
    while (   (handle = libssh2_sftp_open(  sftp
                                          , [self.remotePath UTF8String]
                                          , LIBSSH2_FXF_WRITE|LIBSSH2_FXF_CREAT|LIBSSH2_FXF_READ
                                          , LIBSSH2_SFTP_S_IRUSR|LIBSSH2_SFTP_S_IWUSR|
                                          LIBSSH2_SFTP_S_IRGRP|LIBSSH2_SFTP_S_IROTH)) == NULL
           && (libssh2_session_last_errno(session) == LIBSSH2_ERROR_EAGAIN)
           && self.isCancelled == NO) {
        waitsocket(socketFD, session);
    }

    if (handle == NULL) {
        // unable to open
        unsigned long lastError = libssh2_sftp_last_error([self.connection sftp]);
        NSString *errorDescription = [NSString stringWithFormat:@"Unable to open file for writing: SFTP Status Code %ld", lastError];
        self.error = [self errorWithCode:eSFTPClientErrorUnableToOpenFile
                        errorDescription:errorDescription
                         underlyingError:@(lastError)];
        return NO;
    } else {
        self.handle = handle;
        return YES;
    }
}

- (void)start {
    if (   [self pathIsValid:self.localPath] == NO
        || [self pathIsValid:self.remotePath] == NO
        || [self ready] == NO
        || [self checkSftp] == NO) {
        [self.connection requestDidFail:self withError:self.error];
        return;
    }
    // verify local file is readable prior to upload
    if ([[NSFileManager defaultManager] isReadableFileAtPath:self.localPath] == NO) {
        self.error = [self errorWithCode:eSFTPClientErrorUnableToOpenLocalFileForReading
                        errorDescription:@"Local file is not readable"
                         underlyingError:nil];
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    NSError __autoreleasing *attributesError = nil;
    NSDictionary *localFileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.localPath
                                                                                         error:&attributesError];
    if (localFileAttributes == nil) {
        self.error = [self errorWithCode:eSFTPClientErrorUnableToOpenLocalFileForReading
                        errorDescription:@"Unable to get attributes of Local file"
                         underlyingError:@(attributesError.code)];
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    LIBSSH2_SESSION *session = [self.connection session];
    int socketFD = [self.connection socket];

    if ([self openFileHandle] == NO) {
        [self.connection requestDidFail:self withError:self.error];
        return;
    }
    __weak DLSFTPUploadRequest *weakSelf = self;
    dispatch_queue_t socketQueue = dispatch_get_current_queue();
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        void(^cleanup_handler)(int) = ^(int error) {
            if (error) {
                printf("Error creating channel: %d", error);
            }
            NSLog(@"finished reading file for upload, cleaning up channel");
        };

        dispatch_io_t channel = dispatch_io_create_with_path(  DISPATCH_IO_STREAM
                                                             , [weakSelf.localPath UTF8String]
                                                             , O_RDONLY
                                                             , 0
                                                             , dispatch_get_current_queue()
                                                             , cleanup_handler
                                                             );
        dispatch_source_t progressSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
        __block unsigned long long totalBytesSent = 0ull;
        unsigned long long filesize = [localFileAttributes fileSize];
        DLSFTPClientProgressBlock progressBlock = weakSelf.progressBlock;
        dispatch_source_set_event_handler(progressSource, ^{
            totalBytesSent += dispatch_source_get_data(progressSource);
            if (progressBlock) {
                progressBlock(totalBytesSent, filesize);
            }
        });

        dispatch_source_set_cancel_handler(progressSource, ^{
#if NEEDS_DISPATCH_RETAIN_RELEASE
            dispatch_release(progressSource);
#endif
        });
        dispatch_resume(progressSource);

        weakSelf.startTime = [NSDate date];
        weakSelf.read_error = 0;

        // dispatch this block on file io queue

        dispatch_block_t channel_cleanup_block = ^{
            dispatch_source_cancel(progressSource);
            dispatch_io_close(channel, DISPATCH_IO_STOP);
            dispatch_async(socketQueue, ^{ [weakSelf uploadFinished]; });
        }; // end channel cleanup block

        dispatch_io_read(  channel
                         , 0 // for stream, offset is ignored
                         , SIZE_MAX
                         , socketQueue // blocks with data queued on the socket queue
                         , ^(bool done, dispatch_data_t data, int error) {
                             // dispatch_data_apply would be ideal to use here, but the amount of data passed to each block
                             // is decided by dispatch_io_read, and we'd need to chunk it up to fit in the buffer anyways
                             // still, might be better for cancellation
                             // ACTUALLY maybe it can be specified, via the high/low watermark

                             // and dispatch_io_set_interval should help with stalling to cancel

                             // data has been read into dispatch_data_t data
                             // this will be executed on _socketQueue
                             // now loop over the data in sizes smaller than the buffer
                             size_t buffered_chunk_size = MIN(cBufferSize, dispatch_data_get_size(data));
                             size_t offset = 0;
                             const void *buffer;
                             while (   (buffered_chunk_size > 0)
                                    && (offset < dispatch_data_get_size(data))
                                    && weakSelf.isCancelled == NO) {
                                 dispatch_data_t buffered_chunk_subrange = dispatch_data_create_subrange(data, offset, buffered_chunk_size);
                                 size_t bytes_read = 0;
                                 // map the subrange to make sure we have a contiguous buffer
                                 dispatch_data_t mapped_buffered_chunk_subrange = dispatch_data_create_map(buffered_chunk_subrange, &buffer, &bytes_read);

                                 // send the buffer
                                 int sftp_result = 0;
                                 while (   weakSelf.isCancelled == NO
                                        && (sftp_result = libssh2_sftp_write(weakSelf.handle, buffer, bytes_read)) == LIBSSH2SFTP_EAGAIN) {
                                     // update shouldcontinue into the waitsocket file desctiptor
                                     waitsocket(socketFD, session);
                                 }
                                 weakSelf.sftp_result = sftp_result;
#if NEEDS_DISPATCH_RETAIN_RELEASE
                                 dispatch_release(buffered_chunk_subrange);
#endif
                                 mapped_buffered_chunk_subrange = NULL;
                                 offset += bytes_read;
                                 if (sftp_result > 0) {
                                     dispatch_source_merge_data(progressSource, sftp_result);
                                 } else {
                                     // error in SFTP write
                                     dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), channel_cleanup_block);
                                 }
                             }
                             // end of reading while loop in dispatch_io_handler
                             weakSelf.read_error = error;
                             if (done) {
                                 dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), channel_cleanup_block);
                             }
                         }); // end of dispatch_io_read
    });
}

- (void)uploadFinished {
    self.finishTime = [NSDate date];
    int socketFD = [self.connection socket];
    LIBSSH2_SESSION *session = [self.connection session];
    LIBSSH2_SFTP *sftp = [self.connection sftp];

    if (self.isCancelled) {
        // Cancelled by user
        while(libssh2_sftp_close_handle(self.handle) == LIBSSH2SFTP_EAGAIN) {
            waitsocket(socketFD, session);
        }

        // delete remote file on cancel?
        self.error = [self errorWithCode:eSFTPClientErrorCancelledByUser
                        errorDescription:@"Cancelled by user."
                         underlyingError:nil];
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    if (self.read_error != 0) {
        // error reading file
        NSString *errorDescription = [NSString stringWithFormat:@"Read local file failed with code %d", self.read_error];
        self.error = [self errorWithCode:eSFTPClientErrorUnableToReadFile
                        errorDescription:errorDescription
                         underlyingError:@(self.read_error)];
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    if (self.sftp_result < 0) { // error on last call to upload
        // get the error before closing the file
        int result = libssh2_sftp_last_error(sftp);
        while(   (libssh2_sftp_close_handle(self.handle) == LIBSSH2SFTP_EAGAIN)
              && self.isCancelled == NO) {
            waitsocket(socketFD, session);
        }
        if ([self ready] == NO) {
            [self.connection requestDidFail:self withError:self.error];
            return;
        }
        // error writing
        NSString *errorDescription = [NSString stringWithFormat:@"Write file failed with code %d.", result];
        self.error = [self errorWithCode:eSFTPClientErrorUnableToWriteFile
                        errorDescription:errorDescription
                         underlyingError:@(result)];
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    int result;
    // stat the remote file after uploading
    LIBSSH2_SFTP_ATTRIBUTES attributes;
    while (   ((result = libssh2_sftp_fstat(self.handle, &attributes)) == LIBSSH2SFTP_EAGAIN)
           && self.isCancelled == NO){
        waitsocket(socketFD, session);
    }
    if ([self ready] == NO) {
        [self.connection requestDidFail:self withError:self.error];
        return; }
    if (result) {
        // unable to stat the file
        NSString *errorDescription = [NSString stringWithFormat:@"Unable to stat file: SFTP Status Code %d", result];
        self.error = [self errorWithCode:eSFTPClientErrorUnableToStatFile
                        errorDescription:errorDescription
                         underlyingError:@(result)];
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    // now close the remote handle
    while(   ((result = libssh2_sftp_close_handle(self.handle)) == LIBSSH2SFTP_EAGAIN)
          && self.isCancelled == NO) {
        waitsocket(socketFD, session);
    }
    if ([self ready] == NO) {
        [self.connection requestDidFail:self withError:self.error];
        return;
    }
    if (result) {
        NSString *errorDescription = [NSString stringWithFormat:@"Close file handle failed with code %d", result];
        self.error = [self errorWithCode:eSFTPClientErrorUnableToCloseFile
                        errorDescription:errorDescription
                         underlyingError:nil];
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    NSDictionary *attributesDictionary = [NSDictionary dictionaryWithAttributes:attributes];
    DLSFTPFile *file = [[DLSFTPFile alloc] initWithPath:self.remotePath
                                             attributes:attributesDictionary];
    self.uploadedFile = file;
    [self.connection requestDidComplete:self];
}

- (void)succeed {
    DLSFTPClientFileTransferSuccessBlock successBlock = self.successBlock;
    DLSFTPFile *uploadedFile = self.uploadedFile;
    NSDate *startTime = self.startTime;
    NSDate *finishTime = self.finishTime;
    if (successBlock) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            successBlock(uploadedFile,startTime,finishTime);
        });
    }
    self.successBlock = nil;
    self.failureBlock = nil;
}

@end
