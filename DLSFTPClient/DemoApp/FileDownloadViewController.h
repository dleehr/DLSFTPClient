//
//  FileDownloadViewController.h
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/19/12.
//  Copyright (c) 2012 Dan Leehr. All rights reserved.
//

#import <UIKit/UIKit.h>

@class DLSFTPFile;
@class DLSFTPConnection;

@interface FileDownloadViewController : UIViewController

- (id)initWithFile:(DLSFTPFile *)file
        connection:(DLSFTPConnection *)connection;

@end
