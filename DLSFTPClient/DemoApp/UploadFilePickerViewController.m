//
//  UploadFilePickerViewController.m
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/31/12.
//  Copyright (c) 2012 Dan Leehr. All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
// 
//  Redistributions of source code must retain the above copyright notice,
//  this list of conditions and the following disclaimer.
// 
//  Redistributions in binary form must reproduce the above copyright
//  notice, this list of conditions and the following disclaimer in the
//  documentation and/or other materials provided with the distribution.
// 
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
// IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
// TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A
// PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
// TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
// PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
// LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
// NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
// SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
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
