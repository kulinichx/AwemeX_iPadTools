#import <UIKit/UIKit.h>

@interface AwemeXCustomInputView : UIView
- (instancetype)initWithTitle:(NSString *)title key:(NSString *)key placeholder:(NSString *)placeholder maxValue:(CGFloat)maxValue;
- (void)reloadValue;
@end
