//
//  DLSFTPMoveRenameRequest.m
//  DLSFTPClient
//
//  Created by Dan Leehr on 3/9/13.
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

#import "DLSFTPMoveRenameRequest.h"
#import "DLSFTPConnection.h"
#import "DLSFTPFile.h"
#import "NSDictionary+SFTPFileAttributes.h"

@interface DLSFTPMoveRenameRequest ()

@property (nonatomic, copy) NSString *remotePath;
@property (nonatomic, copy) NSString *newPath;
@property (nonatomic, strong) DLSFTPFile *movedItem;

@end

@implementation DLSFTPMoveRenameRequest

- (id)initWithRemotePath:(NSString *)remotePath
                 newPath:(NSString *)newPath
            successBlock:(DLSFTPClientFileMetadataSuccessBlock)successBlock
            failureBlock:(DLSFTPClientFailureBlock)failureBlock {
    self = [super init];
    if(self) {
        self.remotePath = remotePath;
        self.newPath = newPath;
        self.successBlock = successBlock;
        self.failureBlock = failureBlock;
    }
    return self;
}

- (void)start {
    if (   [self pathIsValid:self.remotePath] == NO
        || [self pathIsValid:self.newPath] == NO
        || [self ready] == NO
        || [self checkSftp] == NO) {
        [self.connection requestDidFail:self withError:self.error];
        return;
    }
    LIBSSH2_SESSION *session = [self.connection session];
    LIBSSH2_SFTP *sftp = [self.connection sftp];
    int socketFD = [self.connection socket];
    int result;

    // libssh2_sftp_rename includes overwrite | atomic | native
    while(  ((result = (libssh2_sftp_rename(sftp, [self.remotePath UTF8String], [self.newPath UTF8String]))) == LIBSSH2SFTP_EAGAIN)
          && self.isCancelled == NO) {
        waitsocket(socketFD, session);
    }

    if ([self ready] == NO) {
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    if (result) {
        // unable to rename
        NSString *errorDescription = [NSString stringWithFormat:@"Unable to rename item: SFTP Status Code %d", result];
        self.error = [self errorWithCode:eSFTPClientErrorUnableToRename
                        errorDescription:errorDescription
                         underlyingError:@(result)];
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    // item renamed, stat the new item
    // can use stat since we don't need a descriptor
    LIBSSH2_SFTP_ATTRIBUTES attributes;
    while (  ((result = libssh2_sftp_stat(sftp, [self.newPath UTF8String], &attributes)) == LIBSSH2SFTP_EAGAIN)
           && self.isCancelled == NO) {
        waitsocket(socketFD, session);
    }

    if ([self ready] == NO) {
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    if (result) {
        // unable to stat the new item
        NSString *errorDescription = [NSString stringWithFormat:@"Unable to stat newly renamed item: SFTP Status Code %d", result];
        self.error = [self errorWithCode:eSFTPClientErrorUnableToStatFile
                        errorDescription:errorDescription
                         underlyingError:@(result)];
        [self.connection requestDidFail:self withError:self.error];
        return;
    }

    // attributes are valid
    NSDictionary *attributesDictionary = [NSDictionary dictionaryWithAttributes:attributes];
    DLSFTPFile *movedItem = [[DLSFTPFile alloc] initWithPath:self.newPath
                                                  attributes:attributesDictionary];
    self.movedItem = movedItem;
    [self.connection requestDidComplete:self];
}

- (void)succeed {
    DLSFTPClientFileMetadataSuccessBlock successBlock = self.successBlock;
    DLSFTPFile *movedItem = self.movedItem;
    if (successBlock) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            successBlock(movedItem);
        });
    }
    self.successBlock = nil;
    self.failureBlock = nil;
}

@end
