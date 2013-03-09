//
//  FileBrowserViewController.m
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/19/12.
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

#import "FileBrowserViewController.h"
#import "DLSFTPFile.h"
#import "DLSFTPConnection.h"
#import "DLSFTPListFilesRequest.h"
#import "DLSFTPMakeDirectoryRequest.h"
#import "DLFileSizeFormatter.h"
#import "FileDownloadViewController.h"
#import "UploadFilePickerViewController.h"
#import "FileOperationsViewController.h"
#import "DLDocumentsDirectoryPath.h"

static NSString * cRootPath = @"/";

@interface FileBrowserViewController () <UIAlertViewDelegate> {
    DLSFTPConnection *_connection;
}

@property (copy, nonatomic) NSArray *files;
@property (copy, nonatomic) NSString *path;

@end

@implementation FileBrowserViewController

- (id)initWithSFTPConnection:(DLSFTPConnection *)connection {
    return [self initWithSFTPConnection:connection
                                   path:cRootPath];
}

- (id)initWithSFTPConnection:(DLSFTPConnection *)connection
                        path:(NSString *)path {
    if ((connection == nil) || (path == nil)) {
        self = nil;
        return self;
    }
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _connection = connection;
        self.path = path;
        self.title = [_path lastPathComponent];
        UIBarButtonItem *uploadPickerButton = [[UIBarButtonItem alloc] initWithTitle:@"Upload File"
                                                                               style:UIBarButtonItemStyleBordered
                                                                              target:self
                                                                              action:@selector(showUploadPicker:)];
        UIBarButtonItem *createDirectoryButton = [[UIBarButtonItem alloc] initWithTitle:@"Create Directory"
                                                                                  style:UIBarButtonItemStyleBordered
                                                                                 target:self
                                                                                 action:@selector(createDirectory:)];
        self.toolbarItems = @[ uploadPickerButton, createDirectoryButton ];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    // Display logout button only for root paths
    if ([_path isEqualToString:cRootPath]) {
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Logout"
                                                                                 style:UIBarButtonItemStyleDone
                                                                                target:self
                                                                                action:@selector(logoutTapped:)];
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    self.files = nil;
}

- (NSArray *)files {
    if (_files != nil) {
        return _files;
    }

    __weak FileBrowserViewController *weakSelf = self;

    DLSFTPClientArraySuccessBlock successBlock = ^(NSArray *files) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.files = files;
            if (weakSelf.isViewLoaded) {
                [weakSelf.tableView reloadData];
            }
        });
    };
    
    DLSFTPClientFailureBlock failureBlock = ^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *title = [NSString stringWithFormat:@"%@ Error: %d", error.domain, error.code];
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:title
                                                                message:[error localizedDescription]
                                                               delegate:nil
                                                      cancelButtonTitle:@"OK"
                                                      otherButtonTitles:nil];
            [alertView show];
        });
    };

    // begin loading files
    DLSFTPRequest *request = [[DLSFTPListFilesRequest alloc] initWithDirectoryPath:_path
                                                                      successBlock:successBlock
                                                                      failureBlock:failureBlock];
    [_connection submitRequest:request];
    return @[ ];
}



#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.files count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:CellIdentifier];
        cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
    }

    DLSFTPFile *file = [self.files objectAtIndex:indexPath.row];
    cell.textLabel.text = file.filename;
    static DLFileSizeFormatter *formatter = nil;
    if (formatter == nil) {
        formatter = [[DLFileSizeFormatter alloc] init];
    }
    if ([[file.attributes fileType] isEqualToString:NSFileTypeDirectory]) {
        cell.detailTextLabel.text = nil;
    } else {
        cell.detailTextLabel.text = [formatter stringFromSize:file.attributes.fileSize];
    }

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    DLSFTPFile *file = [self.files objectAtIndex:indexPath.row];
    UIViewController *viewController = nil;
    if(   [file.attributes.fileType isEqualToString:NSFileTypeDirectory]
       || [file.attributes.fileType isEqualToString:NSFileTypeSymbolicLink]) {
        NSString *nextPath = [_path stringByAppendingPathComponent:file.filename];
        viewController = [[FileBrowserViewController alloc] initWithSFTPConnection:_connection
                                                                              path:nextPath];
    } else {
        viewController = [[FileDownloadViewController alloc] initWithFile:file
                                                               connection:_connection];
        viewController.hidesBottomBarWhenPushed = YES;
    }
    [self.navigationController pushViewController:viewController
                                         animated:YES];
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
    DLSFTPFile *file = [self.files objectAtIndex:indexPath.row];
    FileOperationsViewController *viewController = [[FileOperationsViewController alloc] initWithFile:file
                                                                                           connection:_connection];
    viewController.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:viewController animated:YES];
}

- (void)logoutTapped:(id)sender {
    UIBarButtonItem *logoutButton = self.navigationItem.leftBarButtonItem;
    logoutButton.enabled = NO;
    [_connection disconnect];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)showUploadPicker:(id)sender {
    
    UploadFilePickerViewController *viewController = [[UploadFilePickerViewController alloc] initWithPath:DLDocumentsDirectoryPath()
                                                                                               connection:_connection
                                                                                               remotePath:self.path];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:viewController];
    [self.navigationController presentViewController:navigationController
                                            animated:YES
                                          completion:nil];
}

- (void)createDirectory:(id)sender {
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Create Directory"
                                                        message:@"Enter the new directory name:"
                                                       delegate:self
                                              cancelButtonTitle:@"Cancel"
                                              otherButtonTitles:@"Create", nil];

    alertView.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *alertViewTextField = [alertView textFieldAtIndex:0];
    alertViewTextField.keyboardType = UIKeyboardTypeASCIICapable;
    alertViewTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    alertViewTextField.autocorrectionType = UITextAutocorrectionTypeNo;

    [alertView show];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (buttonIndex != alertView.cancelButtonIndex) {
        // not cancelled
        NSString *makeDirectoryName = [[alertView textFieldAtIndex:0] text];
        NSString *makeDirectoryPath = [self.path stringByAppendingPathComponent:makeDirectoryName];
        __weak FileBrowserViewController *weakSelf = self;

        // on success, clear files and reload the table
        DLSFTPClientFileMetadataSuccessBlock successBlock = ^(DLSFTPFile *createdDirectory) {
            weakSelf.files = nil; // clear out files
            [weakSelf.tableView reloadData];
        };

        DLSFTPClientFailureBlock failureBlock = ^(NSError *error) {
            NSString *errorString = [NSString stringWithFormat:@"Error %d", error.code];
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:errorString
                                                                message:error.localizedDescription
                                                               delegate:nil
                                                      cancelButtonTitle:@"OK"
                                                      otherButtonTitles:nil];
            [alertView show];
        };
        DLSFTPRequest *request = [[DLSFTPMakeDirectoryRequest alloc] initWithDirectoryPath:makeDirectoryPath
                                                                              successBlock:successBlock
                                                                              failureBlock:failureBlock];
        [_connection submitRequest:request];
    }
}

@end
