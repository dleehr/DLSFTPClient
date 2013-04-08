//
//  FileUploadViewController.m
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/30/12.
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

#import "FileUploadViewController.h"
#import "DLSFTPConnection.h"
#import "DLSFTPFile.h"
#import "DLSFTPRequest.h"
#import "DLSFTPUploadRequest.h"
#import "DLFileSizeFormatter.h"

// TODO: convert table view to show all file attributes

@interface FileUploadViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, weak) DLSFTPConnection *connection;
@property (nonatomic, copy) NSString *remoteBasePath;
@property (nonatomic, copy) NSString *localPath;
@property (nonatomic, strong) DLSFTPRequest *request;
@property (nonatomic, weak) UIProgressView *progressView;
@property (nonatomic, weak) UILabel *progressLabel;

@end

@implementation FileUploadViewController

- (id)initWithConnection:(DLSFTPConnection *)connection
         remoteDirectory:(NSString *)remoteBasePath
           localFilePath:(NSString *)localFilePath {
    self = [super initWithStyle:UITableViewStyleGrouped];
    if (self) {
        self.connection = connection;
        self.remoteBasePath = remoteBasePath;
        self.localPath = localFilePath;
        self.title = [NSString stringWithFormat:@"Upload to %@", [remoteBasePath lastPathComponent]];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    // file name and details
    CGFloat buttonHeight = 44.0f;
    CGFloat padding = 10.0f;
    CGFloat progressHeight = 9.0f;

    // lower rect for buttons
    UIView *lowerView = [[UIView alloc] initWithFrame:CGRectMake(  0.0f
                                                                 , 0.0f
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
    progressLabel.backgroundColor = self.view.backgroundColor;
    progressLabel.textAlignment = UITextAlignmentRight;
    [lowerView addSubview:progressLabel];
    self.progressLabel = progressLabel;

    CGFloat buttonWidth = roundf((CGRectGetWidth(lowerView.bounds) - padding) / 2.0f);
    UIButton *startButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    startButton.frame = CGRectMake(  CGRectGetMinX(lowerView.bounds) + padding
                                   , CGRectGetMaxY(_progressLabel.frame) + padding
                                   , buttonWidth
                                   , buttonHeight);
    startButton.backgroundColor = self.view.backgroundColor;
    [startButton setTitle:@"Upload" forState:UIControlStateNormal];
    [startButton addTarget:self
                    action:@selector(startTapped:)
          forControlEvents:UIControlEventTouchUpInside
     ];

    UIButton *cancelButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    cancelButton.frame = CGRectMake(  CGRectGetMaxX(startButton.frame) + padding
                                    , CGRectGetMaxY(_progressLabel.frame) + padding
                                    , buttonWidth
                                    , buttonHeight);
    cancelButton.backgroundColor = self.view.backgroundColor;
    [cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];

    [cancelButton addTarget:self
                     action:@selector(cancelTapped:)
           forControlEvents:UIControlEventTouchUpInside
     ];

    [lowerView addSubview:startButton];
    [lowerView addSubview:cancelButton];

    // progress view
    UIProgressView *progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    progressView.frame = CGRectMake(  CGRectGetMinX(lowerView.bounds) + padding
                                     , CGRectGetMaxY(cancelButton.frame) + padding
                                     , CGRectGetWidth(lowerView.bounds)
                                     , progressHeight);
    progressView.backgroundColor = self.view.backgroundColor;

    [lowerView addSubview:progressView];
    _progressView = progressView;
    
    CGRect lowerViewFrame = lowerView.frame;
    lowerViewFrame.size.height = buttonHeight * 2.0f + progressHeight + 3.0f * padding;
    lowerViewFrame.origin.y = (CGRectGetMaxY(self.view.bounds) - CGRectGetHeight(lowerViewFrame));
    lowerView.frame = lowerViewFrame;

    self.tableView.tableFooterView = lowerView;

}


#pragma mark UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellIdentifier = @"CellIdentifier";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:cellIdentifier];
    }
    static DLFileSizeFormatter *formatter = nil;
    if (formatter == nil) {
        formatter = [[DLFileSizeFormatter alloc] init];
    }
    cell.textLabel.text = [self.localPath lastPathComponent];
    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.localPath
                                                                                    error:nil];
    cell.detailTextLabel.text = [formatter stringFromSize:[fileAttributes fileSize]];
    return cell;
}

#pragma mark Button Handlers

- (void)startTapped:(id)sender {
    self.progressLabel.text = nil;
    self.progressView.progress = 0.0f;

    __weak FileUploadViewController *weakSelf = self;
    __block UIBackgroundTaskIdentifier taskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [weakSelf.request cancel];
    }];
    DLSFTPClientProgressBlock progressBlock = ^void(unsigned long long bytesSent, unsigned long long bytesTotal) {
        float progress = (float)bytesSent / (float)bytesTotal;
        dispatch_async(dispatch_get_main_queue(), ^{
            weakSelf.progressView.progress = progress;
            static DLFileSizeFormatter *formatter = nil;
            if (formatter == nil) {
                formatter = [[DLFileSizeFormatter alloc] init];
            }
            NSString *sentString = [formatter stringFromSize:bytesSent];
            NSString *totalString = [formatter stringFromSize:bytesTotal];

            weakSelf.progressLabel.text = [NSString stringWithFormat:@"%@ / %@", sentString, totalString];
        });
    };

    DLSFTPClientFileTransferSuccessBlock successBlock = ^(DLSFTPFile *file, NSDate *startTime, NSDate *finishTime) {
        dispatch_async(dispatch_get_main_queue(), ^{        
            NSTimeInterval duration = round([finishTime timeIntervalSinceDate:startTime]);
            DLFileSizeFormatter *formatter = [[DLFileSizeFormatter alloc] init];
            unsigned long long rate = (file.attributes.fileSize / duration);
            NSString *rateString = [formatter stringFromSize:rate];

            NSString *alertMessage = [NSString stringWithFormat:@"Uploaded %@ in %.1fs\n %@/sec", file.filename, duration, rateString];
            UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Upload completed"
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

    NSString *localFilename = [self.localPath lastPathComponent];
    NSString *remotePath = [self.remoteBasePath stringByAppendingPathComponent:localFilename];
    self.request = [[DLSFTPUploadRequest alloc] initWithRemotePath:remotePath
                                                         localPath:self.localPath
                                                      successBlock:successBlock
                                                      failureBlock:failureBlock
                                                     progressBlock:progressBlock];
    [self.connection submitRequest:self.request];
}

- (void)cancelTapped:(id)sender {
    [self.request cancel];
}


@end
