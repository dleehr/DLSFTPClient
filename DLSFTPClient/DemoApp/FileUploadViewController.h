//
//  FileUploadViewController.h
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/30/12.
//  Copyright (c) 2012 Dan Leehr. All rights reserved.
//

#import <UIKit/UIKit.h>

@class DLSFTPConnection;
@interface FileUploadViewController : UIViewController

- (id)initWithConnection:(DLSFTPConnection *)connection
         remoteDirectory:(NSString *)remoteBasePath
           localFilePath:(NSString *)localFilePath;

@end
