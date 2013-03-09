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
               localpath:(NSString *)localPath
           progressBlock:(DLSFTPClientProgressBlock)progressBlock
            successBlock:(DLSFTPClientFileTransferSuccessBlock)successBlock
            failureBlock:(DLSFTPClientFailureBlock)failureBlock;
@end
