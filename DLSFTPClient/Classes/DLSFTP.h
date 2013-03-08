//
//  DLSFTPRequestDelegate.h
//  DLSFTPClient
//
//  Created by Dan Leehr on 3/6/13.
//  Copyright (c) 2013 Dan Leehr. All rights reserved.
//
#import <Foundation/Foundation.h>
#include <fcntl.h>
#include <sys/socket.h>
#include <arpa/inet.h>
#include "libssh2.h"
#include "libssh2_config.h"
#include "libssh2_sftp.h"

// Error Definitions

extern NSString * const SFTPClientErrorDomain;
extern NSString * const SFTPClientUnderlyingErrorKey;

typedef enum {
    eSFTPClientErrorUnknown = 1,
    eSFTPClientErrorNotImplemented,
    eSFTPClientErrorOperationInProgress,
    eSFTPClientErrorInvalidArguments,
    eSFTPClientErrorAlreadyConnected,
    eSFTPClientErrorConnectionTimedOut,
    eSFTPClientErrorSocketError,
    eSFTPClientErrorUnableToConnect,
    eSFTPClientErrorUnableToInitializeSession,
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
    eSFTPClientErrorUnableToRename
} eSFTPClientErrorCode;


@class DLSFTPFile;
@class DLSFTPRequest;

// Block typedefs
typedef void(^DLSFTPClientSuccessBlock)(void);
typedef void(^DLSFTPClientFailureBlock)(NSError *error);
typedef void(^DLSFTPClientArraySuccessBlock)(NSArray *array); // Array of DLSFTPFile objects
typedef void(^DLSFTPClientProgressBlock) (unsigned long long bytesReceived, unsigned long long bytesTotal); // return NO for cancel
typedef void(^DLSFTPClientFileTransferSuccessBlock)(DLSFTPFile *file, NSDate *startTime, NSDate *finishTime);
typedef void(^DLSFTPClientFileMetadataSuccessBlock)(DLSFTPFile *fileOrDirectory);

@protocol DLSFTPRequestDelegate <NSObject>

- (int)socket;
- (LIBSSH2_SESSION *)session;
- (LIBSSH2_SFTP *)sftp;

@end
