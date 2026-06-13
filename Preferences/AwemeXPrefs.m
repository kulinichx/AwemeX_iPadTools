#import "AwemeXPrefs.h"
#import <Preferences/PSSpecifier.h>

@implementation AwemeXPrefsListController
- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [[self loadSpecifiersFromPlistName:@"Root" target:self] retain];
    }
    return _specifiers;
}
@end
