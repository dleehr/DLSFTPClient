//
//  LocalFilesViewController.m
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/24/12.
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

#import "LocalFilesViewController.h"
#import "DLFileSizeFormatter.h"

@interface LocalFilesViewController () <UIDocumentInteractionControllerDelegate>

@property (nonatomic, strong) UIDocumentInteractionController *interactionController;

@end

@implementation LocalFilesViewController

- (id)initWithPath:(NSString *)path
{
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        _path = path;
        _files = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:path
                                                                     error:NULL] mutableCopy];
        self.title = [path lastPathComponent];
        self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Dismiss"
                                                                                 style:UIBarButtonItemStyleDone
                                                                                target:self
                                                                                action:@selector(dismissTapped:)];
        self.navigationItem.rightBarButtonItem = self.editButtonItem;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.tableView.allowsMultipleSelectionDuringEditing = YES;
}

- (void)dismissTapped:(id)sender {
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)selectAllTapped:(id)sender {

    for (NSUInteger row=0;row<[self.files count]; row++) {
        [self.tableView selectRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:0]
                                    animated:YES
                              scrollPosition:UITableViewScrollPositionNone];
    }
}

- (void)deleteTapped:(id)sender {
    [self.tableView beginUpdates];
    NSMutableIndexSet *deletedIndexes = [[NSMutableIndexSet alloc] init];
    NSMutableArray *deletedIndexPaths = [[NSMutableArray alloc] init];
    for (NSIndexPath *indexPath in self.tableView.indexPathsForSelectedRows) {
        NSUInteger index = indexPath.row;
        NSString *filePath = [self.path stringByAppendingPathComponent:[self.files objectAtIndex:index]];
        if ([[NSFileManager defaultManager] removeItemAtPath:filePath error:NULL]) {
            [deletedIndexPaths addObject:indexPath];
            [deletedIndexes addIndex:index];
        }
    }
    [self.files removeObjectsAtIndexes:deletedIndexes];
    [self.tableView deleteRowsAtIndexPaths:deletedIndexPaths withRowAnimation:UITableViewRowAnimationMiddle];
    [self.tableView endUpdates];
    [self setEditing:NO animated:YES];
}


#pragma mark - Table view data source
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.files count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *CellIdentifier = @"Cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:CellIdentifier];
    }

    NSString *filename = [self.files objectAtIndex:indexPath.row];
    cell.textLabel.text = filename;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[self.path stringByAppendingPathComponent:filename]
                                                                                error:NULL];
    static DLFileSizeFormatter *formatter = nil;
    if (formatter == nil) {
        formatter = [[DLFileSizeFormatter alloc] init];
    }
    if ([[attributes fileType] isEqualToString:NSFileTypeDirectory]) {
        cell.detailTextLabel.text = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        cell.detailTextLabel.text = [formatter stringFromSize:attributes.fileSize];
        cell.accessoryType = UITableViewCellAccessoryNone;
    }

    cell.selectionStyle = UITableViewCellSelectionStyleGray;
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    return YES;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the row from the data source
        NSString *filename = [self.files objectAtIndex:indexPath.row];
        NSString *filepath = [self.path stringByAppendingPathComponent:filename];
        NSError __autoreleasing *error = nil;
        if([[NSFileManager defaultManager] removeItemAtPath:filepath error:&error]) {
            [self.files removeObjectAtIndex:indexPath.row];
            [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
        } else {
            NSString *message = [NSString stringWithFormat:@"%@", error];
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Error deleting file"
                                                                message:message
                                                               delegate:nil
                                                      cancelButtonTitle:@"OK"
                                                      otherButtonTitles:nil];
            [alertView show];
        }
    }
}

- (void)setEditing:(BOOL)editing animated:(BOOL)animated {
    [super setEditing:editing animated:animated];
    if (editing) {
        UIBarButtonItem *deleteButton = [[UIBarButtonItem alloc] initWithTitle:@"Delete"
                                                                         style:UIBarButtonItemStyleBordered
                                                                        target:self
                                                                        action:@selector(deleteTapped:)];
        deleteButton.tintColor = [UIColor colorWithRed:0.8f green:0.0f blue:0.0f alpha:1.0f];
        deleteButton.width = 120.0f;
        UIBarButtonItem *selectAllButton = [[UIBarButtonItem alloc] initWithTitle:@"Select All"
                                                                            style:UIBarButtonItemStyleBordered
                                                                           target:self
                                                                           action:@selector(selectAllTapped:)];
        selectAllButton.width = 120.0f;
        UIBarButtonItem *flexibleSpace = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                                       target:nil
                                                                                       action:nil];
        [self setToolbarItems:@[ deleteButton, flexibleSpace, selectAllButton] animated:animated];
    } else {
        [self setToolbarItems:nil animated:animated];
    }
    [self.navigationController setToolbarHidden:!editing animated:animated];
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (tableView.editing == NO) {
        NSString *filename = [self.files objectAtIndex:indexPath.row];
        NSString *filepath = [self.path stringByAppendingPathComponent:filename];
        NSURL *fileURL = [NSURL fileURLWithPath:filepath];

        // document interaction
        self.interactionController = [UIDocumentInteractionController interactionControllerWithURL:fileURL];
        self.interactionController.delegate = self;
        [self.interactionController presentOptionsMenuFromRect:[tableView rectForRowAtIndexPath:indexPath]
                                                        inView:tableView
                                                      animated:YES];

        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    }
}

#pragma mark - UIDocumentInteractionControllerDelegate

- (UIViewController *)documentInteractionControllerViewControllerForPreview:(UIDocumentInteractionController *)controller {
    return self.navigationController;
}


@end
