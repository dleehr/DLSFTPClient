//
//  FileOperationsViewController.m
//  DLSFTPClient
//
//  Created by Dan Leehr on 9/3/12.
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

#import "FileOperationsViewController.h"
#import "DLSFTPFile.h"
#import "DLSFTPConnection.h"
#import "DLSFTPRemoveFileRequest.h"
#import "DLSFTPMoveRenameRequest.h"

typedef enum {
      eAlertViewTypeDelete
    , eAlertViewTypeRename
} eAlertViewType;

@interface FileOperationsViewController () <UIAlertViewDelegate>

@property (nonatomic, weak) DLSFTPConnection *connection;
@property (nonatomic, strong) DLSFTPFile *file; // strong because on rename it gets replaced

@end

@implementation FileOperationsViewController

- (id)initWithFile:(DLSFTPFile *)file
        connection:(DLSFTPConnection *)connection {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.file = file;
        self.connection = connection;
        self.title = [file filename];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor];

    CGFloat buttonHeight = 44.0f;
    CGFloat padding = 10.0f;
    /* -[  ]-[  ]-[  ]- */
    CGFloat buttonWidth = roundf((CGRectGetWidth(self.view.bounds) - (padding * 4.0f)) / 3.0f);

    /* show permissions */
    // 3x3

    UIButton *deleteButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    deleteButton.frame = CGRectMake(  CGRectGetMinX(self.view.bounds) + padding
                                    , CGRectGetMinY(self.view.bounds) + padding
                                    , buttonWidth
                                    , buttonHeight);
    [deleteButton setTitle:@"Delete" forState:UIControlStateNormal];
    [deleteButton addTarget:self
                     action:@selector(deleteTapped:)
           forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:deleteButton];

    UIButton *renameButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    renameButton.frame = CGRectMake(  CGRectGetMaxX(deleteButton.frame) + padding
                                    , CGRectGetMinY(self.view.bounds) + padding
                                    , buttonWidth
                                    , buttonHeight);
    [renameButton setTitle:@"Rename" forState:UIControlStateNormal];
    [renameButton addTarget:self
                     action:@selector(renameTapped:)
           forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:renameButton];

    UIButton *moveButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    moveButton.frame = CGRectMake(  CGRectGetMaxX(renameButton.frame) + padding
                                    , CGRectGetMinY(self.view.bounds) + padding
                                    , buttonWidth
                                    , buttonHeight);
    [moveButton setTitle:@"Move" forState:UIControlStateNormal];
    [moveButton addTarget:self
                     action:@selector(moveTapped:)
           forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:moveButton];

}

- (void)deleteTapped:(id)sender {
    NSString *confrimationText = [NSString stringWithFormat:@"Are you sure you want to delete %@", self.file.filename];
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Delete"
                                                        message:confrimationText
                                                       delegate:self
                                              cancelButtonTitle:@"Cancel"
                                              otherButtonTitles:@"Delete", nil];
    alertView.tag = eAlertViewTypeDelete;
    [alertView show];
}

- (void)renameTapped:(id)sender {
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Rename"
                                                        message:@"Enter the new name:"
                                                       delegate:self
                                              cancelButtonTitle:@"Cancel"
                                              otherButtonTitles:@"Create", nil];

    alertView.tag = eAlertViewTypeRename;
    alertView.alertViewStyle = UIAlertViewStylePlainTextInput;
    UITextField *alertViewTextField = [alertView textFieldAtIndex:0];
    alertViewTextField.keyboardType = UIKeyboardTypeASCIICapable;
    alertViewTextField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    alertViewTextField.autocorrectionType = UITextAutocorrectionTypeNo;
    alertViewTextField.text = [self.file filename];
    [alertView show];
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (buttonIndex == alertView.cancelButtonIndex) {
        // cancelled, ignore
        return;
    }
    // check the tag
    switch (alertView.tag) {
        case eAlertViewTypeRename: {
            UITextField *textField = [alertView textFieldAtIndex:0];
            NSString *newFilename = [textField.text lastPathComponent];
            [self renameConfirmedWithNewFilename:newFilename];
            break;
        }
        case eAlertViewTypeDelete: {
            [self deleteConfirmed];
            break;
        }
        default:
            break;
    }
}

- (void)renameConfirmedWithNewFilename:(NSString *)text {
    __weak FileOperationsViewController *weakSelf = self;
    DLSFTPClientFileMetadataSuccessBlock successBlock = ^(DLSFTPFile *renamedItem) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.file = renamedItem;
            weakSelf.title = [renamedItem filename];
        });
    };

    DLSFTPClientFailureBlock failureBlock = ^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *title = [NSString stringWithFormat:@"%@ Error: %ld", error.domain, (long)error.code];
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:title
                                                                message:[error localizedDescription]
                                                               delegate:nil
                                                      cancelButtonTitle:@"OK"
                                                      otherButtonTitles:nil];
            [alertView show];
        });
    };

    NSString *newPath = [[self.file.path stringByDeletingLastPathComponent] stringByAppendingPathComponent:text];
    DLSFTPRequest *request = [[DLSFTPMoveRenameRequest alloc] initWithSourcePath:self.file.path
                                                                 destinationPath:newPath
                                                                    successBlock:successBlock
                                                                    failureBlock:failureBlock];
    [self.connection submitRequest:request];
}

- (void)deleteConfirmed {
    __weak FileOperationsViewController *weakSelf = self;
    DLSFTPClientSuccessBlock successBlock = ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf.navigationController popViewControllerAnimated:YES];
        });
    };

    DLSFTPClientFailureBlock failureBlock = ^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *title = [NSString stringWithFormat:@"%@ Error: %ld", error.domain, (long)error.code];
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:title
                                                                message:[error localizedDescription]
                                                               delegate:nil
                                                      cancelButtonTitle:@"OK"
                                                      otherButtonTitles:nil];
            [alertView show];
        });
    };

    DLSFTPRequest *request = [[DLSFTPRemoveFileRequest alloc] initWithFilePath:self.file.path
                                                                  successBlock:successBlock
                                                                  failureBlock:failureBlock];
    [self.connection submitRequest:request];
}



- (void)moveTapped:(id)sender {
    // push a view controller to pick the new location
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Error"
                                                        message:@"Move not yet implemented in UI"
                                                       delegate:nil
                                              cancelButtonTitle:@"OK"
                                              otherButtonTitles:nil];
    [alertView show];

}

@end
