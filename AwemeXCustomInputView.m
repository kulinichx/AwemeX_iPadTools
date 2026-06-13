#import "AwemeXCustomInputView.h"
#import "AwemeXSettingsHelper.h"

@interface AwemeXCustomInputView () <UITextFieldDelegate>
@end

@implementation AwemeXCustomInputView {
    NSString *_key;
    CGFloat _minValue;
    CGFloat _maxValue;
    CGFloat _defaultValue;
    NSString *_format;
    UILabel *_titleLabel;
    UILabel *_subtitleLabel;
    UISlider *_slider;
    UITextField *_field;
}

- (instancetype)initWithTitle:(NSString *)title subtitle:(NSString *)subtitle key:(NSString *)key minValue:(CGFloat)minValue maxValue:(CGFloat)maxValue defaultValue:(CGFloat)defaultValue valueFormat:(NSString *)format {
    self = [super initWithFrame:CGRectZero];
    if (self) {
        _key = [key copy];
        _minValue = minValue;
        _maxValue = maxValue;
        _defaultValue = defaultValue;
        _format = format.length ? [format copy] : @"%.2f";
        self.backgroundColor = UIColor.clearColor;

        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.text = title;
        _titleLabel.textColor = UIColor.whiteColor;
        _titleLabel.font = [UIFont boldSystemFontOfSize:14];
        [self addSubview:_titleLabel];

        _subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _subtitleLabel.text = subtitle ?: @"";
        _subtitleLabel.textColor = [UIColor colorWithWhite:1 alpha:0.68];
        _subtitleLabel.font = [UIFont systemFontOfSize:11];
        _subtitleLabel.numberOfLines = 2;
        [self addSubview:_subtitleLabel];

        _slider = [[UISlider alloc] initWithFrame:CGRectZero];
        _slider.minimumValue = _minValue;
        _slider.maximumValue = _maxValue;
        [_slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
        [self addSubview:_slider];

        _field = [[UITextField alloc] initWithFrame:CGRectZero];
        _field.textColor = UIColor.whiteColor;
        _field.textAlignment = NSTextAlignmentCenter;
        _field.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
        _field.keyboardType = UIKeyboardTypeDecimalPad;
        _field.delegate = self;
        _field.layer.cornerRadius = 8;
        _field.layer.masksToBounds = YES;
        _field.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.22];
        [self addSubview:_field];

        _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _subtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
        _slider.translatesAutoresizingMaskIntoConstraints = NO;
        _field.translatesAutoresizingMaskIntoConstraints = NO;

        [NSLayoutConstraint activateConstraints:@[
            [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:7],

            [_subtitleLabel.leadingAnchor constraintEqualToAnchor:_titleLabel.leadingAnchor],
            [_subtitleLabel.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:2],
            [_subtitleLabel.trailingAnchor constraintEqualToAnchor:_field.leadingAnchor constant:-8],

            [_field.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-12],
            [_field.topAnchor constraintEqualToAnchor:self.topAnchor constant:9],
            [_field.widthAnchor constraintEqualToConstant:58],
            [_field.heightAnchor constraintEqualToConstant:28],

            [_slider.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:14],
            [_slider.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-14],
            [_slider.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-8],
        ]];

        [self reloadValue];
    }
    return self;
}

- (CGFloat)currentValue {
    id obj = [[NSUserDefaults standardUserDefaults] objectForKey:_key];
    CGFloat value = obj ? [obj doubleValue] : _defaultValue;
    if (!isfinite(value)) value = _defaultValue;
    return MIN(MAX(value, _minValue), _maxValue);
}

- (void)reloadValue {
    CGFloat value = [self currentValue];
    _slider.value = value;
    _field.text = [NSString stringWithFormat:_format, value];
}

- (void)saveValue:(CGFloat)value {
    value = MIN(MAX(value, _minValue), _maxValue);
    _slider.value = value;
    _field.text = [NSString stringWithFormat:_format, value];
    [[AwemeXSettingsHelper shared] setFloat:value forKey:_key];
}

- (void)sliderChanged:(UISlider *)sender { [self saveValue:sender.value]; }
- (BOOL)textFieldShouldReturn:(UITextField *)textField { [textField resignFirstResponder]; return YES; }
- (void)textFieldDidEndEditing:(UITextField *)textField { [self saveValue:[textField.text doubleValue]]; }
@end
