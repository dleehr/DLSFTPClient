//
//  DLSFTPListFilesRequest.m
//  DLSFTPClient
//
//  Created by Dan Leehr on 3/6/13.
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


#import "DLSFTPListFilesRequest.h"
#import "DLSFTPConnection.h"
#import "NSDictionary+SFTPFileAttributes.h"
#import "DLSFTPFile.h"

#include "libssh2.h"

// where to put this globally?
static const size_t cBufferSize = 8192;

@interface DLSFTPListFilesRequest ()

@property (nonatomic, copy) NSString *directoryPath;
@property (nonatomic, copy) NSArray *fileList;
@end

@implementation DLSFTPListFilesRequest

// the request shouldn't be initialized with a connection
- (id)initWithDirectoryPath:(NSString *)directoryPath
               successBlock:(DLSFTPClientArraySuccessBlock)successBlock
               failureBlock:(DLSFTPClientFailureBlock)failureBlock {
    self = [super init];
    if (self) {
        self.successBlock = successBlock;
        self.failureBlock = failureBlock;
        self.directoryPath = directoryPath;
    }
    return self;
}

- (void)start {
    if (   [self pathIsValid:self.directoryPath] == NO
        || [self ready] == NO
        || [self checkSftp] == NO) {
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    LIBSSH2_SESSION *session = [self.connection session];
    LIBSSH2_SFTP *sftp = [self.connection sftp];
    int socketFD = [self.connection socket];
    // get a file handle for reading the directory
    LIBSSH2_SFTP_HANDLE *handle = NULL;
    while(   ((handle = libssh2_sftp_opendir(sftp, [self.directoryPath UTF8String])) == NULL
              && (libssh2_session_last_errno(session) == LIBSSH2_ERROR_EAGAIN))
          && self.isCancelled == NO) {
        waitsocket(socketFD, session);
    }

    if ([self ready] == NO) {
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    if (handle == NULL) {
        // unable to open directory
        unsigned long lastError = libssh2_sftp_last_error(sftp);
        NSString *errorDescription = [NSString stringWithFormat:@"Unable to open directory: sftp error: %ld", lastError];

        // unable to initialize session
        self.error = [self errorWithCode:eSFTPClientErrorUnableToOpenDirectory
                        errorDescription:errorDescription
                         underlyingError:@(lastError)];
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    char buffer[cBufferSize];
    LIBSSH2_SFTP_ATTRIBUTES attributes;
    NSMutableArray *fileList = [[NSMutableArray alloc] init];
    long result = 0;

    do {
        memset(buffer, 0, sizeof(buffer));
        while (   ((result = libssh2_sftp_readdir(handle, buffer, cBufferSize, &attributes)) == LIBSSH2SFTP_EAGAIN)
               && self.isCancelled == NO){
            waitsocket(socketFD, session);
        }
        if ([self ready] == NO) {
            [self.connection requestDidFail:self withError:self.error];
            return;
        }
        if (result > 0) {
            NSString *filename = [[NSString alloc] initWithBytes:buffer
                                                          length:result
                                                        encoding:NSUTF8StringEncoding];
            // skip . and ..
            if ([filename isEqualToString:@"."] || [filename isEqualToString:@".."]) {
                continue;
            }
            NSString *filepath = [self.directoryPath stringByAppendingPathComponent:filename];
            NSDictionary *attributesDictionary = [NSDictionary dictionaryWithAttributes:attributes];
            DLSFTPFile *file = [[DLSFTPFile alloc] initWithPath:filepath
                                                     attributes:attributesDictionary];
            [fileList addObject:file];
        }
    } while (result > 0);

    if (result < 0) {
        result = libssh2_sftp_last_error(sftp);
        while (   ((libssh2_sftp_closedir(handle)) == LIBSSH2SFTP_EAGAIN)
               && self.isCancelled == NO) {
            waitsocket(socketFD, session);
        }
        // error reading
        NSString *errorDescription = [NSString stringWithFormat:@"Read directory failed with code %ld", result];
        self.error = [self errorWithCode:eSFTPClientErrorUnableToReadDirectory
                        errorDescription:errorDescription
                         underlyingError:@(result)];
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    // close the handle
    while((   (result = libssh2_sftp_closedir(handle)) == LIBSSH2SFTP_EAGAIN)
          && self.isCancelled == NO){
        waitsocket(socketFD, session);
    }
    if (result) {
        NSString *errorDescription = [NSString stringWithFormat:@"Close directory handle failed with code %ld", result];
        self.error = [self errorWithCode:eSFTPClientErrorUnableToCloseDirectory
                        errorDescription:errorDescription
                         underlyingError:@(result)];
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    [fileList sortUsingSelector:@selector(compare:)];
    self.fileList = fileList;
    [self.connection requestDidComplete:self];
}

- (void)succeed {
    DLSFTPClientArraySuccessBlock successBlock = self.successBlock;
    NSArray *fileList = self.fileList;
    if (successBlock) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            successBlock(fileList);
        });
    }
    self.successBlock = nil;
    self.failureBlock = nil;
}

@end
