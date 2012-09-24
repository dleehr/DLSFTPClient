//
//  DLFileSizeFormatter.m
//  DLSFTPClient
//
//  Created by Dan Leehr on 8/19/12.
//  Copyright (c) 2012 Dan Leehr. All rights reserved.
//

#import "DLFileSizeFormatter.h"

@interface DLFileSizeFormatter () {
    NSNumberFormatter *_formatter;
}

@end

@implementation DLFileSizeFormatter

- (id)init {
    self = [super init];
    if (self) {
        _formatter = [[NSNumberFormatter alloc] init];
        _formatter.locale = [NSLocale currentLocale];
        _formatter.numberStyle = NSNumberFormatterDecimalStyle;
        _formatter.maximumFractionDigits = 2;
    }
    return self;
}

- (NSString *)stringFromSize:(unsigned long long)size {
    int exponent = 0;
    unsigned long long tmpsize = size;

    while (tmpsize >>= 1)  {
        ++exponent;
    }

    double sizeDouble = size;

    NSString *units = @"B";
    if ((exponent >= 10) && (exponent < 20)) {
        units = @"KB";
        sizeDouble = sizeDouble / (1llu << 10);
    } else if ((exponent >= 20) && (exponent < 30)) {
        units = @"MB";
        sizeDouble = sizeDouble / (1llu << 20);
    } else if (exponent >= 30) {
        units = @"GB";
        sizeDouble = sizeDouble / (1llu << 30);
    }

    NSString *formattedNumber = [_formatter stringFromNumber:@(sizeDouble)];
    return [NSString stringWithFormat:@"%@ %@", formattedNumber, units];
}

@end
