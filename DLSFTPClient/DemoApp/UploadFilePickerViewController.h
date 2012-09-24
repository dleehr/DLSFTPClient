//
//  UploadFilePickerViewController.h
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/31/12.
//  Copyright (c) 2012 Dan Leehr. All rights reserved.
//

#import "LocalFilesViewController.h"

@class DLSFTPConnection;
@interface UploadFilePickerViewController : LocalFilesViewController

- (id)initWithPath:(NSString *)path
        connection:(DLSFTPConnection *)connection
        remotePath:(NSString *)remotePath;

@property (nonatomic, weak) DLSFTPConnection *connection;
@property (nonatomic, copy) NSString *remotePath;

@end
