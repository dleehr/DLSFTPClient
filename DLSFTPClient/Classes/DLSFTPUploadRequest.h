//
//  DLSFTPUploadRequest.h
//  DLSFTPClient
//
//  Created by Dan Leehr on 3/8/13.
//  Copyright (c) 2013 Dan Leehr. All rights reserved.
//

#import "DLSFTPRequest.h"

@interface DLSFTPUploadRequest : DLSFTPRequest

- (id)initWithRemotePath:(NSString *)remotePath
               localPath:(NSString *)localPath
            successBlock:(DLSFTPClientFileTransferSuccessBlock)successBlock
            failureBlock:(DLSFTPClientFailureBlock)failureBlock
           progressBlock:(DLSFTPClientProgressBlock)progressBlock;

@end
