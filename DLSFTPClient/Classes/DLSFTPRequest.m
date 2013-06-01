//
//  DLSFTPRequest.m
//  DLSFTPClient
//
//  Created by Dan Leehr on 3/4/13.
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

#import "DLSFTPRequest.h"
#import "DLSFTPConnection.h"

static NSString * const DLSFTPRequestNotImplemented = @"DLSFTPRequestMethodNotImplemented";

@interface DLSFTPRequest ()

@property (nonatomic, readwrite, getter = isCancelled) BOOL cancelled;

@end

@implementation DLSFTPRequest

- (void)cancel {
    if (self.cancelHandler) {
        DLSFTPRequestCancelHandler handler = self.cancelHandler;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), handler);
        self.cancelHandler = nil;
    }
    self.cancelled = YES;
}

- (void)start {
    [NSException raise:DLSFTPRequestNotImplemented
                format:@"Request does not implement start"];
}

- (void)succeed {
    [NSException raise:DLSFTPRequestNotImplemented
                format:@"Request does not implement finish"];
}

// potentially move these to the connection
- (BOOL)ready {
    if (self.isCancelled) {
        self.error = [self errorWithCode:eSFTPClientErrorCancelledByUser
                        errorDescription:@"Cancelled by user"
                         underlyingError:nil];
        return NO;
    }
    if ([self.connection isConnected] == NO) {
        self.error = [self errorWithCode:eSFTPClientErrorNotConnected
                        errorDescription:@"Socket not connected"
                         underlyingError:nil];
        return NO;
    }
    return YES;
}
- (BOOL)pathIsValid:(NSString *)path {
    if ([path length] == 0) {
        self.error = [self errorWithCode:eSFTPClientErrorInvalidPath
                        errorDescription:@"Invalid path"
                         underlyingError:nil];
        return NO;
    }
    return YES;
}

- (BOOL)checkSftp {
    LIBSSH2_SESSION *session = [self.connection session];
    LIBSSH2_SFTP *sftp = [self.connection sftp];
    if (sftp == NULL) {
        // unable to initialize sftp
        int lastError = libssh2_session_last_errno(session);
        char *errmsg = NULL;
        int errmsg_len = 0;
        libssh2_session_last_error(session, &errmsg, &errmsg_len, 0);
        NSString *errorDescription = [NSString stringWithFormat:@"Unable to initialize sftp: libssh2 session error %s: %d"
                                      , errmsg
                                      , lastError];
        self.error = [self errorWithCode:eSFTPClientErrorUnableToInitializeSFTP
                        errorDescription:errorDescription
                         underlyingError:nil];
        return NO;
    }
    return YES;
    
}

- (NSError *)errorWithCode:(eSFTPClientErrorCode)errorCode
          errorDescription:(NSString *)errorDescription
           underlyingError:(NSNumber *)underlyingError {
    NSError *error = nil;
    if (underlyingError == nil) {
        error = [NSError errorWithDomain:SFTPClientErrorDomain
                                    code:errorCode
                                userInfo:@{ NSLocalizedDescriptionKey : errorDescription }
                 ];
    } else {
        error = [NSError errorWithDomain:SFTPClientErrorDomain
                                    code:errorCode
                                userInfo:@{ NSLocalizedDescriptionKey : errorDescription, SFTPClientUnderlyingErrorKey : underlyingError }
                 ];
    }
    return error;
}

- (void)fail {
    DLSFTPClientFailureBlock failureBlock = self.failureBlock;
    NSError *error = self.error;
    if (failureBlock) {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            failureBlock(error);
        });
    }
    self.successBlock = nil;
    self.failureBlock = nil;
}

@end
