//
//  DLSFTPConnection.h
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/11/12.
//  Copyright (c) 2012 Dan Leehr. All rights reserved.
//

#import <Foundation/Foundation.h>

// Error Definitions

extern NSString * const SFTPClientErrorDomain;
extern NSString * const SFTPClientUnderlyingErrorKey;

typedef enum {
    eSFTPClientErrorUnknown = 1,
    eSFTPClientErrorOperationInProgress,
    eSFTPClientErrorInvalidArguments,
    eSFTPClientErrorAlreadyConnected,
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

// Block Definitions

@class DLSFTPFile;

typedef void(^DLSFTPClientSuccessBlock)(void);
typedef void(^DLSFTPClientFailureBlock)(NSError *error);
typedef void(^DLSFTPClientArraySuccessBlock)(NSArray *array); // Array of DLSFTPFile objects
typedef BOOL(^DLSFTPClientProgressBlock) (unsigned long long bytesReceived, unsigned long long bytesTotal); // return NO for cancel
typedef void(^DLSFTPClientFileTransferSuccessBlock)(DLSFTPFile *file, NSDate *startTime, NSDate *finishTime);
typedef void(^DLSFTPClientFileMetadataSuccessBlock)(DLSFTPFile *fileOrDirectory);


@interface DLSFTPConnection : NSObject

#pragma mark Connection


- (id)initWithHostname:(NSString *)hostname
                  port:(NSUInteger)port
              username:(NSString *)username
              password:(NSString *)password;

- (id)initWithHostname:(NSString *)hostname
              username:(NSString *)username
              password:(NSString *)password;

- (void)connectWithSuccessBlock:(DLSFTPClientSuccessBlock)successBlock
                   failureBlock:(DLSFTPClientFailureBlock)failureBlock;

- (void)disconnect;
- (BOOL)isConnected;

#pragma mark Directory Operations

- (void)listFilesInDirectory:(NSString *)directoryPath
                successBlock:(DLSFTPClientArraySuccessBlock)successBlock
                failureBlock:(DLSFTPClientFailureBlock)failureBlock;

- (void)makeDirectory:(NSString *)directoryPath
         successBlock:(DLSFTPClientFileMetadataSuccessBlock)successBlock
         failureBlock:(DLSFTPClientFailureBlock)failureBlock;

#pragma mark Metadata Operations

- (void)renameOrMoveItemAtRemotePath:(NSString *)remotePath
                         withNewPath:(NSString *)newPath
                        successBlock:(DLSFTPClientFileMetadataSuccessBlock)successBlock
                        failureBlock:(DLSFTPClientFailureBlock)failureBlock;

- (void)removeItemAtPath:(NSString *)remotePath
            successBlock:(DLSFTPClientSuccessBlock)successBlock
            failureBlock:(DLSFTPClientFailureBlock)failureBlock;

#pragma mark File Transfer
// progressBlock uses dispatch_source_merge_data and will be queued on main thread.
// It may not reach 100%, intended to be used for UI updates only

- (void)downloadFileAtRemotePath:(NSString *)remotePath
                     toLocalPath:(NSString *)localPath
                   progressBlock:(DLSFTPClientProgressBlock)progressBlock
                    successBlock:(DLSFTPClientFileTransferSuccessBlock)successBlock
                    failureBlock:(DLSFTPClientFailureBlock)failureBlock;

- (void)uploadFileToRemotePath:(NSString *)remotePath
                 fromLocalPath:(NSString *)localPath
                 progressBlock:(DLSFTPClientProgressBlock)progressBlock
                  successBlock:(DLSFTPClientFileTransferSuccessBlock)successBlock
                  failureBlock:(DLSFTPClientFailureBlock)failureBlock;

- (void)cancelTransfer;

@end
