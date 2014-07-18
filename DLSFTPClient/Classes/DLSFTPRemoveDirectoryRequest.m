//
//  DLSFTPRemoveDirectoryRequest.m
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

#import "DLSFTPRemoveDirectoryRequest.h"
#import "DLSFTPConnection.h"

@interface DLSFTPRemoveDirectoryRequest ()

@property (nonatomic, copy) NSString *directoryPath;

@end

@implementation DLSFTPRemoveDirectoryRequest

- (id)initWithDirectoryPath:(NSString *)directoryPath
               successBlock:(DLSFTPClientSuccessBlock)successBlock
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
    long result;
    while(  ((result = (libssh2_sftp_rmdir(sftp, [self.directoryPath UTF8String]))) == LIBSSH2SFTP_EAGAIN)
          && self.isCancelled == NO) {
        waitsocket(socketFD, session);
    }

    if ([self ready] == NO) {
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    if (result) {
        // unable to remove
        NSString *errorDescription = [NSString stringWithFormat:@"Unable to remove directory: SFTP Status Code %ld", result];
        self.error = [self errorWithCode:eSFTPClientErrorUnableToRemove
                        errorDescription:errorDescription
                         underlyingError:@(result)];
        [self.connection requestDidFail:self withError:self.error];
        return;
    }
    [self.connection requestDidComplete:self];
}

- (void)succeed {
    DLSFTPClientSuccessBlock successBlock = self.successBlock;
    if (successBlock) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            successBlock();
        });
    }
    self.successBlock = nil;
    self.failureBlock = nil;
}

@end
