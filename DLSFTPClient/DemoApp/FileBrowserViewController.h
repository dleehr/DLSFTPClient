//
//  FileBrowserViewController.h
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/19/12.
//  Copyright (c) 2012 Dan Leehr. All rights reserved.
//

#import <UIKit/UIKit.h>

@class DLSFTPConnection;

@interface FileBrowserViewController : UITableViewController

// initialize with a logged-in sftp connection
- (id)initWithSFTPConnection:(DLSFTPConnection *)connection;
- (id)initWithSFTPConnection:(DLSFTPConnection *)connection
                        path:(NSString *)path;
@end
