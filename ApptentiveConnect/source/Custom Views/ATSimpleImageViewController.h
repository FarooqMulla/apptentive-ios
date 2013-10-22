//
//  ATSimpleImageViewController.h
//  ApptentiveConnect
//
//  Created by Andrew Wooster on 3/27/11.
//  Copyright 2011 Apptentive, Inc.. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "ATFeedback.h"
#import "ATFeedbackTypes.h"

@class ATCenteringImageScrollView;

NSString * const ATImageViewChoseImage;

@protocol ATSimpleImageViewControllerDelegate;

@interface ATSimpleImageViewController : UIViewController <UIActionSheetDelegate, UIScrollViewDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UIPopoverControllerDelegate> {
@private
	NSObject<ATSimpleImageViewControllerDelegate> *delegate;
	ATCenteringImageScrollView *scrollView;
	BOOL shouldResign;
	UIView *containerView;
	BOOL isFromCamera;
	
	UIPopoverController *imagePickerPopover;
	UIActionSheet *imageActionSheet;
}
@property (nonatomic, retain) IBOutlet UIView *containerView;

- (id)initWithDelegate:(NSObject<ATSimpleImageViewControllerDelegate> *)delegate;
- (IBAction)donePressed:(id)sender;
- (IBAction)takePhoto:(id)sender;
@end

@protocol ATSimpleImageViewControllerDelegate <NSObject>
- (void)imageViewController:(ATSimpleImageViewController *)vc pickedImage:(UIImage *)image fromSource:(ATFeedbackImageSource)source;
- (void)imageViewControllerWillDismiss:(ATSimpleImageViewController *)vc animated:(BOOL)animated;
/*! Not always called. */
- (void)imageViewControllerDidDismiss:(ATSimpleImageViewController *)vc;
- (ATFeedbackAttachmentOptions)attachmentOptionsForImageViewController:(ATSimpleImageViewController *)vc;

@optional
- (UIImage *)defaultImageForImageViewController:(ATSimpleImageViewController *)vc;
@end
