//
//  FileOperationsViewController.h
//  DLSFTPClient
//
//  Created by Dan Leehr on 9/3/12.
//  Copyright (c) 2012 Dan Leehr. All rights reserved.
//

// UI for deleting, renaming, moving, and changing permissions

#import <UIKit/UIKit.h>

@class DLSFTPFile;
@class DLSFTPConnection;

@interface FileOperationsViewController : UIViewController

- (id)initWithFile:(DLSFTPFile *)file
        connection:(DLSFTPConnection *)connection;

@end
