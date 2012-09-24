//
//  DLDocumentsDirectoryPath.m
//  DLSFTPClient
//
//  Created by Dan Leehr on 9/22/12.
//  Copyright (c) 2012 Dan Leehr. All rights reserved.
//

#import "DLDocumentsDirectoryPath.h"

NSString * DLDocumentsDirectoryPath() {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectoryPath = [paths objectAtIndex:0];
    return documentsDirectoryPath;
}
