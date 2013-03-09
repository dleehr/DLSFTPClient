//
//  FileDownloadViewController.m
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

#import "FileDownloadViewController.h"
#import "DLSFTPFile.h"
#import "DLSFTPConnection.h"
#import "DLSFTPDownloadRequest.h"
#import "DLFileSizeFormatter.h"
#import "DLDocumentsDirectoryPath.h"

@interface FileDownloadViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, weak) DLSFTPFile *file;
@property (nonatomic, weak) DLSFTPConnection *connection;
@property (nonatomic, strong) DLSFTPRequest *request;
@property (nonatomic, weak) UIProgressView *progressView;
@property (nonatomic, weak) UILabel *progressLabel;

@end

@implementation FileDownloadViewController

- (id)initWithFile:(DLSFTPFile *)file connection:(DLSFTPConnection *)connection {
    if ((file == nil) || (connection == nil)) {
        self = nil;
        return self;
    }
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        self.file = file;
        self.connection = connection;
        self.title = file.filename;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor groupTableViewBackgroundColor];

    // file name and details
    CGFloat buttonHeight = 44.0f;
    CGFloat padding = 10.0f;
    CGFloat progressHeight = 9.0f;

    // lower rect for buttons
    UIView *lowerView = [[UIView alloc] initWithFrame:CGRectMake(  CGRectGetMinX(self.view.bounds) + padding
                                                                 , CGRectGetMaxY(self.view.bounds)
                                                                 , CGRectGetWidth(self.view.bounds) - 2.0f * padding
                                                                 , buttonHeight + progressHeight + 2.0f * padding)];
    lowerView.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
    lowerView.backgroundColor = [UIColor clearColor];
    lowerView.autoresizesSubviews = NO;

    // progress label
    UILabel *progressLabel = [[UILabel alloc] initWithFrame:CGRectMake(  CGRectGetMinX(lowerView.bounds) + padding
                                                                       , CGRectGetMinY(lowerView.bounds)
                                                                       , CGRectGetWidth(lowerView.bounds) - padding * 2.0f
                                                                       , buttonHeight)];
    progressLabel.backgroundColor = [UIColor clearColor];
    progressLabel.textAlignment = UITextAlignmentRight;
    [lowerView addSubview:progressLabel];
    self.progressLabel = _progressLabel;

    CGFloat buttonWidth = roundf((CGRectGetWidth(lowerView.bounds) - padding) / 2.0f);
    UIButton *startButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    startButton.frame = CGRectMake(  CGRectGetMinX(lowerView.bounds)
                                   , CGRectGetMaxY(progressLabel.frame) + padding
                                   , buttonWidth
                                   , buttonHeight);
    startButton.backgroundColor = [UIColor clearColor];
    [startButton setTitle:@"Download" forState:UIControlStateNormal];
    [startButton addTarget:self
                    action:@selector(startTapped:)
          forControlEvents:UIControlEventTouchUpInside
     ];

    UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    cancelButton.frame = CGRectMake(  CGRectGetMaxX(startButton.frame) + padding
                                    , CGRectGetMaxY(progressLabel.frame) + padding
                                    , buttonWidth
                                    , buttonHeight);
    cancelButton.backgroundColor = [UIColor clearColor];
    [cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];

    [cancelButton addTarget:self
                     action:@selector(cancelTapped:)
           forControlEvents:UIControlEventTouchUpInside
     ];

    [lowerView addSubview:startButton];
    [lowerView addSubview:cancelButton];

    // progress view
    UIProgressView *progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    progressView.frame = CGRectMake(  CGRectGetMinX(lowerView.bounds)
                                     , CGRectGetMaxY(cancelButton.frame) + padding
                                     , CGRectGetWidth(lowerView.bounds)
                                     , progressHeight);
    progressView.backgroundColor = [UIColor greenColor];
    
    [lowerView addSubview:progressView];
    self.progressView = progressView;
    CGRect lowerViewFrame = lowerView.frame;
    lowerViewFrame.size.height = buttonHeight * 2.0f + progressHeight + 3.0f * padding;
    lowerViewFrame.origin.y = (CGRectGetMaxY(self.view.bounds) - CGRectGetHeight(lowerViewFrame));
    lowerView.frame = lowerViewFrame;

    [self.view addSubview:lowerView];

    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectMake(  CGRectGetMinX(self.view.bounds)
                                                                           , CGRectGetMinY(self.view.bounds)
                                                                           , CGRectGetWidth(self.view.bounds)
                                                                           , CGRectGetHeight(self.view.bounds) - CGRectGetHeight(lowerViewFrame))
                                                          style:UITableViewStyleGrouped];
    tableView.allowsSelection = NO;
    tableView.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    tableView.delegate = self;
    tableView.dataSource = self;

    [self.view addSubview:tableView];
}

#pragma mark UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.file.attributes count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"CellIdentifier";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellIdentifier];
    }
    NSArray *sortedKeys = [[self.file.attributes allKeys] sortedArrayUsingSelector:@selector(compare:)];
    NSString *key = [sortedKeys objectAtIndex:indexPath.row];
    id value = [self.file.attributes objectForKey:key];
    cell.textLabel.text = key;
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@", value];
    return cell;
}

#pragma mark Button Handlers

- (void)startTapped:(id)sender {
    self.progressLabel.text = nil;
    self.progressView.progress = 0.0f;
    
    __weak FileDownloadViewController *weakSelf = self;
    __block UIBackgroundTaskIdentifier taskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [weakSelf.request cancel];
    }];
    DLSFTPClientProgressBlock progressBlock = ^void(unsigned long long bytesReceived, unsigned long long bytesTotal) {
        dispatch_async(dispatch_get_main_queue(), ^{
            float progress = (float)bytesReceived / (float)bytesTotal;
            weakSelf.progressView.progress = progress;
            static DLFileSizeFormatter *formatter = nil;
            if (formatter == nil) {
                formatter = [[DLFileSizeFormatter alloc] init];
            }
            NSString *receivedString = [formatter stringFromSize:bytesReceived];
            NSString *totalString = [formatter stringFromSize:bytesTotal];

            weakSelf.progressLabel.text = [NSString stringWithFormat:@"%@ / %@", receivedString, totalString];
        });
    };

    DLSFTPClientFileTransferSuccessBlock successBlock = ^(DLSFTPFile *file, NSDate *startTime, NSDate *finishTime) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSTimeInterval duration = round([finishTime timeIntervalSinceDate:startTime]);
            DLFileSizeFormatter *formatter = [[DLFileSizeFormatter alloc] init];
            unsigned long long rate = (file.attributes.fileSize / duration);
            NSString *rateString = [formatter stringFromSize:rate];
            weakSelf.progressLabel.text = nil;

            NSString *alertMessage = [NSString stringWithFormat:@"Downloaded %@ in %.1fs\n %@/sec", file.filename, duration, rateString];
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Download completed"
                                                                message:alertMessage
                                                               delegate:nil
                                                      cancelButtonTitle:@"OK"
                                                      otherButtonTitles:nil];
            [alertView show];
            [[UIApplication sharedApplication] endBackgroundTask:taskIdentifier];
        });
    };

    DLSFTPClientFailureBlock failureBlock = ^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *errorString = [NSString stringWithFormat:@"Error %d", error.code];
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:errorString
                                                                message:error.localizedDescription
                                                               delegate:nil
                                                      cancelButtonTitle:@"OK"
                                                      otherButtonTitles:nil];
            [alertView show];
            [[UIApplication sharedApplication] endBackgroundTask:taskIdentifier];
        });
    };

    NSString *remotePath = self.file.path;

    self.request = [[DLSFTPDownloadRequest alloc] initWithRemotePath:remotePath
                                                           localPath:[DLDocumentsDirectoryPath() stringByAppendingPathComponent:self.file.filename]
                                                              resume:NO
                                                        successBlock:successBlock
                                                        failureBlock:failureBlock
                                                       progressBlock:progressBlock];
    [self.connection submitRequest:self.request];
}

- (void)cancelTapped:(id)sender {
    [self.request cancel];
}

@end
