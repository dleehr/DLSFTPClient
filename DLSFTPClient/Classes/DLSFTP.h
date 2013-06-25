//
//  DLSFTPRequestDelegate.h
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

#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include "libssh2.h"
#include "libssh2_config.h"
#include "libssh2_sftp.h"

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= 60000
#define NEEDS_DISPATCH_RETAIN_RELEASE 0
#else                                         // iOS 5.X or earlier
#define NEEDS_DISPATCH_RETAIN_RELEASE 1
#endif

// Error Definitions

extern NSString * const SFTPClientErrorDomain;
extern NSString * const SFTPClientUnderlyingErrorKey;

typedef enum {
    eSFTPClientErrorUnknown = 1,
    eSFTPClientErrorNotImplemented,
    eSFTPClientErrorOperationInProgress,
    eSFTPClientErrorInvalidHostname,
    eSFTPClientErrorInvalidUsername,
    eSFTPClientErrorInvalidPasswordOrKey,
    eSFTPClientErrorInvalidPath,
    eSFTPClientErrorAlreadyConnected,
    eSFTPClientErrorConnectionTimedOut,
    eSFTPClientErrorUnableToResolveHostname,
    eSFTPClientErrorSocketError,
    eSFTPClientErrorUnableToConnect,
    eSFTPClientErrorUnableToInitializeSession,
    eSFTPClientErrorDisconnected,
    eSFTPClientErrorHandshakeFailed,
    eSFTPClientErrorAuthenticationFailed,
    eSFTPClientErrorNotConnected,
    eSFTPClientErrorUnableToInitializeSFTP,
    eSFTPClientErrorUnableToOpenDirectory,
    eSFTPClientErrorUnableToCloseDirectory,
    eSFTPClientErrorUnableToOpenFile,
    eSFTPClientErrorUnableToCloseFile,
    eSFTPClientErrorUnableToOpenLocalFileForWriting,
    eSFTPClientErrorUnableToReadDirectory,
    eSFTPClientErrorUnableToReadFile,
    eSFTPClientErrorUnableToStatFile,
    eSFTPClientErrorUnableToCreateChannel,
    eSFTPClientErrorCancelledByUser,
    eSFTPClientErrorUnableToOpenLocalFileForReading,
    eSFTPClientErrorUnableToWriteFile,
    eSFTPClientErrorUnableToMakeDirectory,
    eSFTPClientErrorUnableToRename,
    eSFTPClientErrorUnableToRemove
} eSFTPClientErrorCode;


@class DLSFTPFile;
@class DLSFTPRequest;

// Block typedefs
typedef void(^DLSFTPClientSuccessBlock)(void);
typedef void(^DLSFTPClientFailureBlock)(NSError *error);
typedef void(^DLSFTPClientArraySuccessBlock)(NSArray *array); // Array of DLSFTPFile objects
typedef void(^DLSFTPClientProgressBlock) (unsigned long long bytesReceived, unsigned long long bytesTotal);
typedef void(^DLSFTPClientFileTransferSuccessBlock)(DLSFTPFile *file, NSDate *startTime, NSDate *finishTime);
typedef void(^DLSFTPClientFileMetadataSuccessBlock)(DLSFTPFile *fileOrDirectory);

@protocol DLSFTPRequestDelegate <NSObject>

// requests should call this when they are complete
- (void)requestDidFail:(DLSFTPRequest *)request withError:(NSError *)error;
- (void)requestDidComplete:(DLSFTPRequest *)request;

- (int)socket;
- (LIBSSH2_SESSION *)session;
- (LIBSSH2_SFTP *)sftp;

@end
