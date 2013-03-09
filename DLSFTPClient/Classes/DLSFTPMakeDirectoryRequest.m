//
//  DLSFTPMakeDirectoryRequest.m
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

#import "DLSFTPMakeDirectoryRequest.h"
#import "DLSFTPConnection.h"
#import "DLSFTPFile.h"
#import "NSDictionary+SFTPFileAttributes.h"

@interface DLSFTPMakeDirectoryRequest ()

@property (nonatomic, copy) NSString *directoryPath;
@property (nonatomic, strong) DLSFTPFile *createdDirectory;

@end

@implementation DLSFTPMakeDirectoryRequest

- (id)initWithDirectoryPath:(NSString *)directoryPath
               successBlock:(DLSFTPClientFileMetadataSuccessBlock)successBlock
               failureBlock:(DLSFTPClientFailureBlock)failureBlock {
    self = [super init];
    if (self) {
        self.directoryPath = directoryPath;
        self.successBlock = successBlock;
        self.failureBlock = failureBlock;
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

    // sftp is now valid
    // try to make the directory 0755
    long mode = (LIBSSH2_SFTP_S_IRWXU|
                 LIBSSH2_SFTP_S_IRGRP|LIBSSH2_SFTP_S_IXGRP|
                 LIBSSH2_SFTP_S_IROTH|LIBSSH2_SFTP_S_IXOTH);

    int result;
    while(  ((result = (libssh2_sftp_mkdir(sftp, [self.directoryPath UTF8String], mode))) == LIBSSH2SFTP_EAGAIN)
          && self.isCancelled == NO) {
        waitsocket(socketFD, session);
    }

    if ([self ready] == NO) {
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    if (result) {
        // unable to make the directory
        NSString *errorDescription = [NSString stringWithFormat:@"Unable to make directory: SFTP Status Code %d", result];
        self.error = [self errorWithCode:eSFTPClientErrorUnableToMakeDirectory
                        errorDescription:errorDescription
                         underlyingError:@(result)];
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    // Directory made, stat it.
    // can use stat since we don't need a descriptor
    LIBSSH2_SFTP_ATTRIBUTES attributes;
    while (  ((result = libssh2_sftp_stat(sftp, [self.directoryPath UTF8String], &attributes)) == LIBSSH2SFTP_EAGAIN)
           && self.isCancelled == NO) {
        waitsocket(socketFD, session);
    }

    if ([self ready] == NO) {
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    if (result) {
        // unable to stat the directory
        NSString *errorDescription = [NSString stringWithFormat:@"Unable to stat newly created directory: SFTP Status Code %d", result];
        self.error = [self errorWithCode:eSFTPClientErrorUnableToStatFile
                        errorDescription:errorDescription
                         underlyingError:@(result)];
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    // attributes are valid
    NSDictionary *attributesDictionary = [NSDictionary dictionaryWithAttributes:attributes];
    self.createdDirectory = [[DLSFTPFile alloc] initWithPath:self.directoryPath
                                                  attributes:attributesDictionary];
    [self.connection requestDidComplete:self];
}

- (void)succeed {
    DLSFTPClientFileMetadataSuccessBlock successBlock = self.successBlock;
    DLSFTPFile *createdDirectory = self.createdDirectory;
    if (successBlock) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            successBlock(createdDirectory);
        });
    }
    self.successBlock = nil;
    self.failureBlock = nil;
}

@end
