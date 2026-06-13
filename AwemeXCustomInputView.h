#import <UIKit/UIKit.h>

@interface AwemeXCustomInputView : UIView
- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle key:(NSString *)key minValue:(CGFloat)minValue maxValue:(CGFloat)maxValue defaultValue:(CGFloat)defaultValue valueFormat:(NSString *)format;
- (void)reloadValue;
@end
