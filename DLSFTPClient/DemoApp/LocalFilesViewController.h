//
//  LocalFilesViewController.h
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/24/12.
//  Copyright (c) 2012 Dan Leehr. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "DLSFTPConnection.h"

@interface LocalFilesViewController : UITableViewController

- (id)initWithPath:(NSString *)path;

@property (nonatomic, copy, readonly) NSString *path;
@property (nonatomic, copy, readonly) NSMutableArray *files;

@end
