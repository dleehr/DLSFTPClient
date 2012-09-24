//
//  UploadFilePickerViewController.m
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/31/12.
//  Copyright (c) 2012 Dan Leehr. All rights reserved.
//

#import "UploadFilePickerViewController.h"
#import "FileUploadViewController.h"

@interface UploadFilePickerViewController ()

@end

@implementation UploadFilePickerViewController

- (id)initWithPath:(NSString *)path
        connection:(DLSFTPConnection *)connection
        remotePath:(NSString *)remotePath {
    self = [super initWithPath:path];
    if (self) {
        self.connection = connection;
        self.remotePath = remotePath;
        self.navigationItem.rightBarButtonItem = nil;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.allowsMultipleSelectionDuringEditing = NO;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [super tableView:tableView cellForRowAtIndexPath:indexPath];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return NO;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *file = [self.files objectAtIndex:indexPath.row];
    NSString *localFilePath = [self.path stringByAppendingPathComponent:file];
    FileUploadViewController *uploadViewController = [[FileUploadViewController alloc] initWithConnection:self.connection
                                                                                          remoteDirectory:self.remotePath
                                                                                            localFilePath:localFilePath];
    [self.navigationController pushViewController:uploadViewController
                                         animated:YES];

}

@end
