//
//  FileUploadViewController.m
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/30/12.
//  Copyright (c) 2012 Dan Leehr. All rights reserved.
//

#import "FileUploadViewController.h"
#import "DLSFTPConnection.h"
#import "DLSFTPFile.h"
#import "DLFileSizeFormatter.h"

// TODO: convert table view to show all file attributes

@interface FileUploadViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, weak) DLSFTPConnection *connection;
@property (nonatomic, copy) NSString *remoteBasePath;
@property (nonatomic, copy) NSString *localPath;
@property (nonatomic, readwrite, assign) BOOL cancelled;
@property (nonatomic, weak) UIProgressView *progressView;
@property (nonatomic, weak) UILabel *progressLabel;

@end

@implementation FileUploadViewController

- (id)initWithConnection:(DLSFTPConnection *)connection
         remoteDirectory:(NSString *)remoteBasePath
           localFilePath:(NSString *)localFilePath {
    self = [super initWithNibName:nil bundle:nil];
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
    _progressLabel = progressLabel;

    CGFloat buttonWidth = roundf((CGRectGetWidth(lowerView.bounds) - padding) / 2.0f);
    UIButton *startButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    startButton.frame = CGRectMake(  CGRectGetMinX(lowerView.bounds)
                                   , CGRectGetMaxY(_progressLabel.frame) + padding
                                   , buttonWidth
                                   , buttonHeight);
    startButton.backgroundColor = [UIColor clearColor];
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
    _progressView = progressView;
    
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
        weakSelf.cancelled = YES;
    }];
    DLSFTPClientProgressBlock progressBlock = ^BOOL(unsigned long long bytesSent, unsigned long long bytesTotal) {
        float progress = (float)bytesSent / (float)bytesTotal;
        weakSelf.progressView.progress = progress;
        static DLFileSizeFormatter *formatter = nil;
        if (formatter == nil) {
            formatter = [[DLFileSizeFormatter alloc] init];
        }
        NSString *sentString = [formatter stringFromSize:bytesSent];
        NSString *totalString = [formatter stringFromSize:bytesTotal];

        weakSelf.progressLabel.text = [NSString stringWithFormat:@"%@ / %@", sentString, totalString];
        return (weakSelf.cancelled == NO);
    };

    DLSFTPClientFileTransferSuccessBlock successBlock = ^(DLSFTPFile *file, NSDate *startTime, NSDate *finishTime) {
        NSTimeInterval duration = round([finishTime timeIntervalSinceDate:startTime]);
        DLFileSizeFormatter *formatter = [[DLFileSizeFormatter alloc] init];
        unsigned long long rate = (file.attributes.fileSize / duration);
        NSString *rateString = [formatter stringFromSize:rate];
        weakSelf.progressLabel.text = nil;

        NSString *alertMessage = [NSString stringWithFormat:@"Uploaded %@ in %.1fs\n %@/sec", file.filename, duration, rateString];
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Upload completed"
                                                            message:alertMessage
                                                           delegate:nil
                                                  cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil];
        [alertView show];
        [[UIApplication sharedApplication] endBackgroundTask:taskIdentifier];
    };

    DLSFTPClientFailureBlock failureBlock = ^(NSError *error) {
        NSString *errorString = [NSString stringWithFormat:@"Error %d", error.code];
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:errorString
                                                            message:error.localizedDescription
                                                           delegate:nil
                                                  cancelButtonTitle:@"OK"
                                                  otherButtonTitles:nil];
        [alertView show];
        [[UIApplication sharedApplication] endBackgroundTask:taskIdentifier];
    };

    _cancelled = NO;
    NSString *localFilename = [self.localPath lastPathComponent];
    NSString *remotePath = [self.remoteBasePath stringByAppendingPathComponent:localFilename];
    [self.connection uploadFileToRemotePath:remotePath
                              fromLocalPath:self.localPath
                              progressBlock:progressBlock
                               successBlock:successBlock
                               failureBlock:failureBlock];
}

- (void)cancelTapped:(id)sender {
    _cancelled = YES;
}


@end
