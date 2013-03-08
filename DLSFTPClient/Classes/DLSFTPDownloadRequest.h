//
//  DLSFTPDownloadRequest.h
//  DLSFTPClient
//
//  Created by Dan Leehr on 3/7/13.
//  Copyright (c) 2013 Dan Leehr. All rights reserved.
//

#import "DLSFTPRequest.h"

@interface DLSFTPDownloadRequest : DLSFTPRequest

- (id)initWithConnection:(DLSFTPConnection *)connection
              remotePath:(NSString *)remotePath
               localPath:(NSString *)localPath
            shouldresume:(BOOL)shouldResume
            successBlock:(DLSFTPClientFileTransferSuccessBlock)successBlock
            failureBlock:(DLSFTPClientFailureBlock)failureBlock
           progressBlock:(DLSFTPClientProgressBlock)progressBlock;
@end
