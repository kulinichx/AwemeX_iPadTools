#import "AwemeXCustomInputView.h"
#import "AwemeXSettingsHelper.h"

@interface AwemeXCustomInputView () <UITextFieldDelegate>
@end

@implementation AwemeXCustomInputView {
    NSString *_key;
    CGFloat _maxValue;
    UILabel *_titleLabel;
    UISlider *_slider;
    UITextField *_field;
}

- (instancetype)initWithTitle:(NSString *)title key:(NSString *)key placeholder:(NSString *)placeholder maxValue:(CGFloat)maxValue {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _key = [key copy];
        _maxValue = maxValue > 0 ? maxValue : 1.0;
        self.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1];

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.text = title;
        _titleLabel.textColor = UIColor.whiteColor;
        _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
        [self addSubview:_titleLabel];

        _slider = [[UISlider alloc] initWithFrame:CGRectZero];
        _slider.minimumValue = 0;
        _slider.maximumValue = _maxValue;
        [_slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:_slider];

        _field = [[UITextField alloc] initWithFrame:CGRectZero];
        _field.textColor = UIColor.whiteColor;
        _field.textAlignment = NSTextAlignmentCenter;
        _field.font = [UIFont systemFontOfSize:16];
        _field.keyboardType = UIKeyboardTypeDecimalPad;
        _field.placeholder = placeholder;
        _field.delegate = self;
        _field.layer.cornerRadius = 6;
        _field.layer.masksToBounds = YES;
        _field.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1];
        _field.clearButtonMode = UITextFieldViewModeWhileEditing;
        [self addSubview:_field];

        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _slider.translatesAutoresizingMaskIntoConstraints = NO;
        _field.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
            [_titleLabel.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_field.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
            [_field.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_field.widthAnchor constraintEqualToConstant:86],
            [_field.heightAnchor constraintEqualToConstant:36],
            [_slider.leadingAnchor constraintEqualToAnchor:_titleLabel.trailingAnchor constant:16],
            [_slider.trailingAnchor constraintEqualToAnchor:_field.leadingAnchor constant:-16],
            [_slider.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [_slider.widthAnchor constraintGreaterThanOrEqualToConstant:120]
        ]];

        [self reloadValue];
    }
    return self;
}

- (CGFloat)currentValue {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    id obj = [d objectForKey:_key];
    if (!obj) return 0;
    CGFloat value = [obj doubleValue];
    if (!isfinite(value) || value < 0) return 0;
    return MIN(value, _maxValue);
}

- (void)reloadValue {
    CGFloat value = [self currentValue];
    _slider.value = value;
    _field.text = value > 0 ? [NSString stringWithFormat:@"%.2f", value] : @"";
}

- (void)sliderChanged:(UISlider *)sender {
    CGFloat value = sender.value;
    if (value < 0.005) value = 0;
    _field.text = value > 0 ? [NSString stringWithFormat:@"%.2f", value] : @"";
    [[AwemeXSettingsHelper shared] setFloat:value forKey:_key];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
    CGFloat value = [textField.text doubleValue];
    if (!isfinite(value) || value < 0) value = 0;
    value = MIN(value, _maxValue);
    _slider.value = value;
    textField.text = value > 0 ? [NSString stringWithFormat:@"%.2f", value] : @"";
    [[AwemeXSettingsHelper shared] setFloat:value forKey:_key];
}

@end
