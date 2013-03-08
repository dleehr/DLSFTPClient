//
//  DLSFTPListFilesRequest.h
//  DLSFTPClient
//
//  Created by Dan Leehr on 3/6/13.
//  Copyright (c) 2013 Dan Leehr. All rights reserved.
//

#import "DLSFTPRequest.h"

@interface DLSFTPListFilesRequest : DLSFTPRequest

- (id)initWithConnection:(DLSFTPConnection *)connection
           directoryPath:(NSString *)directoryPath
            successBlock:(DLSFTPClientArraySuccessBlock)successBlock
            failureBlock:(DLSFTPClientFailureBlock)failureBlock;

@end
