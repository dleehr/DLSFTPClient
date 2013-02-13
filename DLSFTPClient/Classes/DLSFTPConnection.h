//
//  DLSFTPConnection.h
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/11/12.
//  Copyright (c) 2012 Dan Leehr. All rights reserved.
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

// Request object, for cancelling
@interface DLSFTPRequest : NSObject

@property (nonatomic, readonly, getter = isCancelled) BOOL cancelled;
- (void)cancel;
@end

// Block Definitions

@class DLSFTPFile;

typedef void(^DLSFTPClientSuccessBlock)(void);
typedef void(^DLSFTPClientFailureBlock)(NSError *error);
typedef void(^DLSFTPClientArraySuccessBlock)(NSArray *array); // Array of DLSFTPFile objects
typedef void(^DLSFTPClientProgressBlock) (unsigned long long bytesReceived, unsigned long long bytesTotal); // return NO for cancel
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

- (id)initWithHostname:(NSString *)hostname
                  port:(NSUInteger)port
              username:(NSString *)username
               keypath:(NSString *)keypath
            passphrase:(NSString *)passphrase;

- (id)initWithHostname:(NSString *)hostname
              username:(NSString *)username
               keypath:(NSString *)keypath
            passphrase:(NSString *)passphrase;

- (DLSFTPRequest *)connectWithSuccessBlock:(DLSFTPClientSuccessBlock)successBlock
                              failureBlock:(DLSFTPClientFailureBlock)failureBlock;

- (void)disconnect;
- (void)cancelAllRequests;
- (BOOL)isConnected;
- (NSUInteger)requestCount;

#pragma mark Directory Operations

- (DLSFTPRequest *)listFilesInDirectory:(NSString *)directoryPath
                           successBlock:(DLSFTPClientArraySuccessBlock)successBlock
                           failureBlock:(DLSFTPClientFailureBlock)failureBlock;

- (DLSFTPRequest *)makeDirectory:(NSString *)directoryPath
                    successBlock:(DLSFTPClientFileMetadataSuccessBlock)successBlock
                    failureBlock:(DLSFTPClientFailureBlock)failureBlock;

#pragma mark Metadata Operations

- (DLSFTPRequest *)renameOrMoveItemAtRemotePath:(NSString *)remotePath
                                    withNewPath:(NSString *)newPath
                                   successBlock:(DLSFTPClientFileMetadataSuccessBlock)successBlock
                                   failureBlock:(DLSFTPClientFailureBlock)failureBlock;

- (DLSFTPRequest *)removeFileAtPath:(NSString *)remotePath
            successBlock:(DLSFTPClientSuccessBlock)successBlock
            failureBlock:(DLSFTPClientFailureBlock)failureBlock;

- (DLSFTPRequest *)removeDirectoryAtPath:(NSString *)remotePath
                            successBlock:(DLSFTPClientSuccessBlock)successBlock
                            failureBlock:(DLSFTPClientFailureBlock)failureBlock;


#pragma mark File Transfer
// progressBlock uses dispatch_source_merge_data.
// It may not reach 100%, intended to be used for UI updates only

- (DLSFTPRequest *)downloadFileAtRemotePath:(NSString *)remotePath
                                toLocalPath:(NSString *)localPath
                                     resume:(BOOL)resume
                              progressBlock:(DLSFTPClientProgressBlock)progressBlock
                               successBlock:(DLSFTPClientFileTransferSuccessBlock)successBlock
                               failureBlock:(DLSFTPClientFailureBlock)failureBlock;

- (DLSFTPRequest *)uploadFileToRemotePath:(NSString *)remotePath
                            fromLocalPath:(NSString *)localPath
                            progressBlock:(DLSFTPClientProgressBlock)progressBlock
                             successBlock:(DLSFTPClientFileTransferSuccessBlock)successBlock
                             failureBlock:(DLSFTPClientFailureBlock)failureBlock;

@end
