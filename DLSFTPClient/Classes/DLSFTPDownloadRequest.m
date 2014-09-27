//
//  DLSFTPDownloadRequest.m
//  DLSFTPClient
//
//  Created by Dan Leehr on 3/7/13.
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


#import "DLSFTPDownloadRequest.h"
#import "DLSFTPConnection.h"
#import "DLSFTPFile.h"
#import "NSDictionary+SFTPFileAttributes.h"

//Constants
static const size_t cBufferSize = 8192;

@interface DLSFTPDownloadRequest ()

@property (nonatomic, copy) DLSFTPClientProgressBlock progressBlock;
@property (nonatomic, copy) NSString *remotePath;
@property (nonatomic, copy) NSString *localPath;
@property (nonatomic, strong) NSDate *startTime;
@property (nonatomic, strong) NSDate *finishTime;
@property (nonatomic, strong) DLSFTPFile *downloadedFile;
@property (nonatomic) BOOL shouldResume;

@property (nonatomic) dispatch_io_t channel;
@property (nonatomic) dispatch_semaphore_t semaphore;
@property (nonatomic) dispatch_source_t progressSource;

@property (nonatomic, assign) LIBSSH2_SFTP_HANDLE *handle;

@end

@implementation DLSFTPDownloadRequest

@synthesize progressSource=_progressSource;
@synthesize channel=_channel;
@synthesize semaphore=_semaphore;

- (id)initWithRemotePath:(NSString *)remotePath
               localPath:(NSString *)localPath
                  resume:(BOOL)resumeIfFileExists
            successBlock:(DLSFTPClientFileTransferSuccessBlock)successBlock
            failureBlock:(DLSFTPClientFailureBlock)failureBlock
           progressBlock:(DLSFTPClientProgressBlock)progressBlock {
    self = [super init];
    if (self) {
        self.remotePath = remotePath;
        self.localPath = localPath;
        self.shouldResume = resumeIfFileExists;
        self.successBlock = successBlock;
        self.failureBlock = failureBlock;
        self.progressBlock = progressBlock;
    }
    return self;
}

- (void)dealloc {
#if NEEDS_DISPATCH_RETAIN_RELEASE
    if (_progressSource) {
        dispatch_release(_progressSource);
        _progressSource = NULL;
    }
    if (_semaphore) {
        dispatch_release(_semaphore);
        _semaphore = NULL;
    }
    if (_channel) {
        dispatch_release(_channel);
        _channel = NULL;
    }
#endif
}


- (BOOL)openFileHandle {
    LIBSSH2_SESSION *session = [self.connection session];
    LIBSSH2_SFTP *sftp = [self.connection sftp];
    int socketFD = [self.connection socket];
    LIBSSH2_SFTP_HANDLE *handle = NULL;
    while (   (handle = libssh2_sftp_open(sftp, [self.remotePath UTF8String], LIBSSH2_FXF_READ, 0)) == NULL
           && (libssh2_session_last_errno(session) == LIBSSH2_ERROR_EAGAIN)
           && self.isCancelled == NO) {
        waitsocket(socketFD, session);
    }
    self.handle = handle;
    if (handle == NULL) {
        // unable to open
        unsigned long lastError = libssh2_sftp_last_error([self.connection sftp]);
        NSString *errorDescription = [NSString stringWithFormat:@"Unable to open file for reading: SFTP Status Code %ld", lastError];
        self.error = [self errorWithCode:eSFTPClientErrorUnableToOpenFile
                        errorDescription:errorDescription
                         underlyingError:@(lastError)];
        return NO;
    } else {
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
    unsigned long long resumeOffset = 0ull;
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.localPath] == NO) {
        // File does not exist, create it
        [[NSFileManager defaultManager] createFileAtPath:self.localPath
                                                contents:nil
                                              attributes:nil];
    } else {
        // local file exists, get existing size
        NSError *error = nil;
        NSDictionary *localAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.localPath
                                                                                         error:&error];
        if (error) {
            self.error = [self errorWithCode:eSFTPClientErrorUnableToOpenLocalFileForWriting
                            errorDescription:@"Unable to get attributes (file size) of existing file"
                             underlyingError:@(error.code)];
            [self.connection requestDidFail:self withError:self.error];
            return;
        }

        if(self.shouldResume) {
            resumeOffset = [localAttributes fileSize];
        }
    }

    if ([[NSFileManager defaultManager] isWritableFileAtPath:self.localPath] == NO) {
        self.error = [self errorWithCode:eSFTPClientErrorUnableToOpenLocalFileForWriting
                        errorDescription:@"Local file is not writable"
                         underlyingError:nil];
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    LIBSSH2_SESSION *session = [self.connection session];
    int socketFD = [self.connection socket];

    if ([self openFileHandle] == NO) {
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    // file handle is now open
    LIBSSH2_SFTP_ATTRIBUTES attributes;
    // stat the file
    int result;
    while (  ((result = libssh2_sftp_fstat(self.handle, &attributes)) == LIBSSH2SFTP_EAGAIN)
           && self.isCancelled == NO) {
        waitsocket(socketFD, session);
    }
    // can also check permissions/types
    if (result) {
        // unable to stat the file
        NSString *errorDescription = [NSString stringWithFormat:@"Unable to stat file: SFTP Status Code %d", result];
        self.error = [self errorWithCode:eSFTPClientErrorUnableToStatFile
                        errorDescription:errorDescription
                         underlyingError:@(result)];
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    // Create the file object here since we have the attributes.  Only used by successBlock
    NSDictionary *attributesDictionary = [NSDictionary dictionaryWithAttributes:attributes];
    DLSFTPFile *file = [[DLSFTPFile alloc] initWithPath:self.remotePath
                                             attributes:attributesDictionary];
    self.downloadedFile = file;

    if (self.shouldResume) {
        libssh2_sftp_seek64(self.handle, resumeOffset);
    }

    self.semaphore = dispatch_semaphore_create(0);

    /* Begin dispatch io */
    void(^cleanup_handler)(int) = ^(int error) {
        if (error) {
            printf("Error creating channel: %d", error);
        }
        dispatch_semaphore_signal(self.semaphore);
    };

    int oflag;
    if (self.shouldResume) {
        oflag =   O_APPEND
        | O_WRONLY
        | O_CREAT;
    } else {
        oflag =   O_WRONLY
        | O_CREAT
        | O_TRUNC;
    }

    dispatch_io_t channel = dispatch_io_create_with_path(  DISPATCH_IO_STREAM
                                                         , [self.localPath UTF8String]
                                                         , oflag
                                                         , 0
                                                         , dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,  0   )
                                                         , cleanup_handler
                                                         );
    if (channel == NULL) {
        // Error creating the channel
        NSString *errorDescription = [NSString stringWithFormat:@"Unable to create a channel for writing to %@", self.localPath];
        self.error = [self errorWithCode:eSFTPClientErrorUnableToCreateChannel
                        errorDescription:errorDescription
                         underlyingError:nil];
        [self.connection requestDidFail:self withError:self.error];
        return;
    } else {
        self.channel = channel;
    }
    /* dispatch_io has been created */

    // configure progress source
    dispatch_source_t progressSource = dispatch_source_create(DISPATCH_SOURCE_TYPE_DATA_ADD, 0, 0, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0));
    __block unsigned long long bytesReceived = resumeOffset;
    unsigned long long filesize = attributes.filesize;
    DLSFTPClientProgressBlock progressBlock = self.progressBlock;
    dispatch_source_set_event_handler(progressSource, ^{
        bytesReceived += dispatch_source_get_data(progressSource);
        if (progressBlock) {
            progressBlock(bytesReceived, filesize);
        }
    });
    self.progressSource = progressSource;
    __weak DLSFTPDownloadRequest *weakSelf = self;
    dispatch_source_set_cancel_handler(progressSource, ^{
    #if NEEDS_DISPATCH_RETAIN_RELEASE
        if (weakSelf.progressSource) {
            dispatch_release(weakSelf.progressSource);
            weakSelf.progressSource = NULL;
        }
    #endif
    });
    dispatch_resume(self.progressSource);
     // end of progressSource setup

    self.startTime = [NSDate date];
    // start the first download block
    dispatch_async(self.connection.socketQueue, ^{ [weakSelf downloadChunk]; });
}

- (void)downloadChunk {
    size_t bytesRead = 0;
    char *buffer = malloc(sizeof(char) * cBufferSize);
    while (   self.isCancelled == NO
           && (bytesRead = libssh2_sftp_read(self.handle, buffer, cBufferSize)) == LIBSSH2SFTP_EAGAIN) {
        waitsocket([self.connection socket], [self.connection session]);
    }
    // after data has been read, write it to the channel
    __weak DLSFTPDownloadRequest *weakSelf = self;
    if (bytesRead > 0) {
        @autoreleasepool {
            dispatch_source_merge_data(self.progressSource, bytesRead);
            dispatch_data_t data = dispatch_data_create(buffer, bytesRead, NULL, DISPATCH_DATA_DESTRUCTOR_FREE);
            dispatch_io_write(  self.channel
                              , 0
                              , data
                              , dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)
                              , ^(bool done, dispatch_data_t data, int error) {
                                  // done refers to the chunk of data written
                                  // Tried moving progress reporting here, didn't make much difference
                                  if (error) {
                                      printf("error in dispatch_io_write %d\n", error);
                                  }
                              });
#if NEEDS_DISPATCH_RETAIN_RELEASE
            dispatch_release(data);
#endif
        }
        // read the next chunk
        dispatch_async(self.connection.socketQueue, ^{ [weakSelf downloadChunk]; });
    } else if(bytesRead == 0 || self.isCancelled) { // not a host error if cancelled
        free(buffer);
        dispatch_async(self.connection.socketQueue, ^{ [weakSelf downloadFinished]; });
    } else { //bytesRead < 0
        free(buffer);
        dispatch_async(self.connection.socketQueue, ^{ [weakSelf downloadFailed]; });
    }
}

- (void)downloadFinished {
    // nothing read, done
    self.finishTime = [NSDate date];
    dispatch_source_cancel(self.progressSource);
    dispatch_io_close(self.channel, 0);

    /* End dispatch_io */

    dispatch_semaphore_wait(self.semaphore, DISPATCH_TIME_FOREVER);
#if NEEDS_DISPATCH_RETAIN_RELEASE
    dispatch_release(self.semaphore);
    self.semaphore = NULL;
#endif
    int socketFD = [self.connection socket];
    LIBSSH2_SESSION *session = [self.connection session];
    // now close the remote handle
    int result = 0;
    if (self.handle) {
        while((result = libssh2_sftp_close_handle(self.handle)) == LIBSSH2SFTP_EAGAIN) {
            waitsocket(socketFD, session);
        }
        self.handle = NULL;
    }
    if (result) {
        NSString *errorDescription = [NSString stringWithFormat:@"Close file handle failed with code %d", result];
        self.error = [self errorWithCode:eSFTPClientErrorUnableToCloseFile
                        errorDescription:errorDescription
                         underlyingError:nil];
        [self.connection requestDidFail:self withError:self.error];
        return;
    }
    if (self.isCancelled) {
        // cancelled by user
        if (self.handle) {
            while(libssh2_sftp_close_handle(self.handle) == LIBSSH2SFTP_EAGAIN) {
                waitsocket(socketFD, session);
            }
            self.handle = NULL;
        }

        // delete the file if not resumable
        if (self.shouldResume == NO) {
            NSError __autoreleasing *deleteError = nil;
            if([[NSFileManager defaultManager] removeItemAtPath:self.localPath error:&deleteError] == NO) {
                NSLog(@"Unable to delete unfinished file: %@", deleteError);
            }
        }
        self.error = [self errorWithCode:eSFTPClientErrorCancelledByUser
                        errorDescription:@"Cancelled by user."
                         underlyingError:nil];
        [self.connection requestDidFail:self withError:self.error];
        return;
    } else {
        [self.connection requestDidComplete:self];
    }
}

- (void)downloadFailed {
    // nothing read, done
    self.finishTime = [NSDate date];
    dispatch_source_cancel(self.progressSource);
    dispatch_io_close(self.channel, 0);

    /* End dispatch_io */

    dispatch_semaphore_wait(self.semaphore, DISPATCH_TIME_FOREVER);
#if NEEDS_DISPATCH_RETAIN_RELEASE
    dispatch_release(self.semaphore);
    self.semaphore = NULL;
#endif
    // get the error before closing the file
    unsigned long result = libssh2_sftp_last_error([self.connection sftp]);
    int socketFD = [self.connection socket];
    LIBSSH2_SESSION *session = [self.connection session];
    if (self.handle) {
        while(libssh2_sftp_close_handle(self.handle) == LIBSSH2SFTP_EAGAIN) {
            waitsocket(socketFD, session);
        }
        self.handle = NULL;
    }
    // error reading
    NSString *errorDescription = [NSString stringWithFormat:@"Read file failed with code %lu.", result];
    self.error = [self errorWithCode:eSFTPClientErrorUnableToReadFile
                    errorDescription:errorDescription
                     underlyingError:@(result)];
    [self.connection requestDidFail:self withError:self.error];
}

- (void)succeed {
    DLSFTPClientFileTransferSuccessBlock successBlock = self.successBlock;
    DLSFTPFile *downloadedFile = self.downloadedFile;
    NSDate *startTime = self.startTime;
    NSDate *finishTime = self.finishTime;
    if (successBlock) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            successBlock(downloadedFile,startTime,finishTime);
        });
    }
    self.successBlock = nil;
    self.failureBlock = nil;
}

@end
