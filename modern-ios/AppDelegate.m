#import "AppDelegate.h"
#import <UIKit/UIKit.h>
extern NSArray *PGImportedLibrary(void);
extern NSString *PGImportedImagePath(NSString *name);
extern NSDictionary *PGImportComicCBZ(NSURL *url,NSError **error);
extern BOOL PGRemoveImportedComic(NSString *uid,NSError **error);

static UIImage *PGImage(NSString *path) {
    if(!path.length)return nil;
    BOOL cacheable=([path hasPrefix:@"assets/native_thumbs/"]||[path hasPrefix:@"assets/ipa_original/"]);
    static NSCache *imageCache=nil;
    static dispatch_once_t once;
    dispatch_once(&once,^{imageCache=[NSCache new];imageCache.countLimit=90;});
    UIImage *cached=cacheable?[imageCache objectForKey:path]:nil;
    if(cached)return cached;
    UIImage *image=nil;
    if([path hasPrefix:@"custom/"]){
        NSString *file=PGImportedImagePath(path);
        if(file)image=[UIImage imageWithContentsOfFile:file];
    }else{
        NSURL *root=[[NSBundle mainBundle] URLForResource:@"web" withExtension:nil];
        image=[UIImage imageWithContentsOfFile:[[root URLByAppendingPathComponent:path] path]];
    }
    if(cacheable&&image)[imageCache setObject:image forKey:path];
    return image;
}
static NSArray *PGLibrary(void) {
    NSURL *url=[[NSBundle mainBundle] URLForResource:@"native_catalog" withExtension:@"json"];
    NSData *data=[NSData dataWithContentsOfURL:url];
    NSArray *arr=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    return [arr isKindOfClass:[NSArray class]]?arr:@[];
}
@interface PGPageController : UIViewController <UIScrollViewDelegate>
@property(nonatomic,strong) NSDictionary *issue;
@property(nonatomic,assign) NSInteger page;
@property(nonatomic,strong) UIImageView *image;
@property(nonatomic,strong) UILabel *counter;
@property(nonatomic,strong) UIScrollView *zoom;
@property(nonatomic,strong) UISlider *scrubber;
@property(nonatomic,strong) UIView *topChrome;
@property(nonatomic,strong) UIView *bottomChrome;
@property(nonatomic,assign) BOOL chromeHidden;
@property(nonatomic,strong) UISegmentedControl *spreadSelector;
@property(nonatomic,strong) UILabel *issueTitle;
@property(nonatomic,strong) UIView *endOverlay;
@property(nonatomic,strong) UIButton *bookmarkButton;
@property(nonatomic,strong) UILabel *savedMarker;
@property(nonatomic,assign) BOOL twoPagePreference;
@property(nonatomic,assign) BOOL lastLandscape;

@end
@implementation PGPageController
- (instancetype)initWithIssue:(NSDictionary *)issue {
    if((self=[super init])){
        _issue=issue;
        _page=[[NSUserDefaults standardUserDefaults] integerForKey:[@"native-progress-" stringByAppendingString:issue[@"id"]]];
        _twoPagePreference=[[NSUserDefaults standardUserDefaults] boolForKey:@"native-two-page-mode"];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];self.view.backgroundColor=UIColor.blackColor;
    self.zoom=[UIScrollView new];self.zoom.translatesAutoresizingMaskIntoConstraints=NO;
    self.zoom.minimumZoomScale=1;self.zoom.maximumZoomScale=4;self.zoom.delegate=self;
    self.image=[UIImageView new];self.image.contentMode=UIViewContentModeScaleAspectFit;
    self.image.frame=self.zoom.bounds;self.image.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    [self.zoom addSubview:self.image];[self.view addSubview:self.zoom];
    UIView *top=[UIView new];top.translatesAutoresizingMaskIntoConstraints=NO;top.backgroundColor=[UIColor colorWithWhite:0 alpha:.78];[self.view addSubview:top];self.topChrome=top;
    UIButton *back=[UIButton buttonWithType:UIButtonTypeSystem];back.translatesAutoresizingMaskIntoConstraints=NO;
    [back setTitle:@"‹  My Comics" forState:UIControlStateNormal];[back setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [back addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];[top addSubview:back];
    UIButton *bookmark=[UIButton buttonWithType:UIButtonTypeCustom];
    bookmark.translatesAutoresizingMaskIntoConstraints=NO;
    [bookmark setImage:PGImage(@"assets/ipa_original/bookmark@2x.png") forState:UIControlStateNormal];
    bookmark.imageView.contentMode=UIViewContentModeScaleAspectFit;
    bookmark.accessibilityLabel=@"Bookmark page";
    [bookmark addTarget:self action:@selector(toggleBookmark:) forControlEvents:UIControlEventTouchUpInside];
    UILongPressGestureRecognizer *bookmarkHold=[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(jumpToBookmark:)];
    bookmarkHold.minimumPressDuration=.48;
    [bookmark addGestureRecognizer:bookmarkHold];
    bookmark.accessibilityHint=@"Tap to save this page, press and hold to jump to your saved bookmark.";
    [top addSubview:bookmark];self.bookmarkButton=bookmark;
    [NSLayoutConstraint activateConstraints:@[
        [bookmark.centerYAnchor constraintEqualToAnchor:top.centerYAnchor],
        [bookmark.trailingAnchor constraintEqualToAnchor:top.trailingAnchor constant:UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad?-169:-5],
        [bookmark.widthAnchor constraintEqualToConstant:40],
        [bookmark.heightAnchor constraintEqualToConstant:35]
    ]];
    UILabel *title=[UILabel new];title.text=self.issue[@"title"];title.textColor=UIColor.whiteColor;
    title.font=[UIFont boldSystemFontOfSize:13];title.textAlignment=NSTextAlignmentRight;title.lineBreakMode=NSLineBreakByTruncatingTail;title.translatesAutoresizingMaskIntoConstraints=NO;[top addSubview:title];self.issueTitle=title;
    if(UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad){
      self.spreadSelector=[[UISegmentedControl alloc]initWithItems:@[@"1 Page",@"2 Pages"]];
      self.spreadSelector.selectedSegmentIndex=self.twoPagePreference?1:0;
      [self.spreadSelector setImage:PGImage(@"assets/ipa_original/single_page_spread_white@2x.png") forSegmentAtIndex:0];
      [self.spreadSelector setImage:PGImage(@"assets/ipa_original/two_page_spread_white@2x.png") forSegmentAtIndex:1];
      self.spreadSelector.tintColor=UIColor.whiteColor;
      if([self.spreadSelector respondsToSelector:@selector(setSelectedSegmentTintColor:)])[self.spreadSelector setValue:[UIColor colorWithRed:.10 green:.47 blue:.60 alpha:1] forKey:@"selectedSegmentTintColor"];
      self.spreadSelector.translatesAutoresizingMaskIntoConstraints=NO;
      self.spreadSelector.accessibilityLabel=@"Page viewing mode";
      [self.spreadSelector addTarget:self action:@selector(spreadChanged:) forControlEvents:UIControlEventValueChanged];
      [top addSubview:self.spreadSelector];
      [NSLayoutConstraint activateConstraints:@[
        [self.spreadSelector.trailingAnchor constraintEqualToAnchor:top.trailingAnchor constant:-8],
        [self.spreadSelector.centerYAnchor constraintEqualToAnchor:top.centerYAnchor],
        [self.spreadSelector.widthAnchor constraintEqualToConstant:156],
        [self.spreadSelector.heightAnchor constraintEqualToConstant:29]
      ]];
    }
    UIView *bottom=[UIView new];bottom.translatesAutoresizingMaskIntoConstraints=NO;bottom.backgroundColor=[UIColor colorWithWhite:0 alpha:.78];[self.view addSubview:bottom];self.bottomChrome=bottom;
    self.scrubber=[UISlider new];self.scrubber.translatesAutoresizingMaskIntoConstraints=NO;self.scrubber.minimumValue=0;
    self.scrubber.continuous=NO;
    self.scrubber.accessibilityLabel=@"Comic page scrubber";self.scrubber.minimumTrackTintColor=[UIColor colorWithRed:.97 green:.83 blue:.45 alpha:1];
    self.scrubber.maximumTrackTintColor=[UIColor colorWithWhite:.77 alpha:1];
    [self.scrubber addTarget:self action:@selector(scrubChanged:) forControlEvents:UIControlEventValueChanged];
    [bottom addSubview:self.scrubber];
    self.counter=[UILabel new];self.counter.textColor=UIColor.whiteColor;
    self.counter.font=[UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
    self.counter.textAlignment=NSTextAlignmentCenter;self.counter.translatesAutoresizingMaskIntoConstraints=NO;[bottom addSubview:self.counter];
    [NSLayoutConstraint activateConstraints:@[
      [self.zoom.topAnchor constraintEqualToAnchor:self.view.topAnchor],[self.zoom.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
      [self.zoom.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[self.zoom.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
      [top.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[top.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[top.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[top.heightAnchor constraintEqualToConstant:38],
      [back.leadingAnchor constraintEqualToAnchor:top.leadingAnchor constant:12],[back.centerYAnchor constraintEqualToAnchor:top.centerYAnchor],
      [back.widthAnchor constraintEqualToConstant:115],
      [title.leadingAnchor constraintEqualToAnchor:back.trailingAnchor constant:8],
      [title.trailingAnchor constraintEqualToAnchor:top.trailingAnchor constant:UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad?-214:-48],
      [title.centerYAnchor constraintEqualToAnchor:top.centerYAnchor],
      [bottom.bottomAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor],[bottom.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[bottom.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],[bottom.heightAnchor constraintEqualToConstant:48],
      [self.counter.leadingAnchor constraintEqualToAnchor:bottom.leadingAnchor constant:10],
      [self.counter.centerYAnchor constraintEqualToAnchor:bottom.centerYAnchor],
      [self.counter.widthAnchor constraintEqualToConstant:104],
      [self.scrubber.leadingAnchor constraintEqualToAnchor:self.counter.trailingAnchor constant:10],
      [self.scrubber.trailingAnchor constraintEqualToAnchor:bottom.trailingAnchor constant:-16],
      [self.scrubber.centerYAnchor constraintEqualToAnchor:bottom.centerYAnchor]]];
    UISwipeGestureRecognizer *next=[[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(nextPage)];
    next.direction=UISwipeGestureRecognizerDirectionLeft;
    [self.zoom addGestureRecognizer:next];
    UISwipeGestureRecognizer *previous=[[UISwipeGestureRecognizer alloc]initWithTarget:self action:@selector(previousPage)];
    previous.direction=UISwipeGestureRecognizerDirectionRight;
    [self.zoom addGestureRecognizer:previous];
    UITapGestureRecognizer *tap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(pageTap:)];
    tap.cancelsTouchesInView=NO;[self.zoom addGestureRecognizer:tap];
    UITapGestureRecognizer *doubleTap=[[UITapGestureRecognizer alloc]initWithTarget:self action:@selector(zoomTap:)];
    doubleTap.numberOfTapsRequired=2;[tap requireGestureRecognizerToFail:doubleTap];[self.zoom addGestureRecognizer:doubleTap];
    self.lastLandscape=(self.view.bounds.size.width>self.view.bounds.size.height);
    [self updateSpreadVisibility];
    [self showPage];
}
- (BOOL)usingTwoPage {
    return UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad
        && self.view.bounds.size.width>self.view.bounds.size.height && self.twoPagePreference;
}
- (void)updateSpreadVisibility{
    self.spreadSelector.hidden=!(self.view.bounds.size.width>self.view.bounds.size.height);
}
- (void)spreadChanged:(UISegmentedControl *)control{
    self.twoPagePreference=control.selectedSegmentIndex==1;
    [[NSUserDefaults standardUserDefaults] setBool:self.twoPagePreference forKey:@"native-two-page-mode"];
    [self showPage];
}
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator{
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    BOOL landscape=size.width>size.height;
    [coordinator animateAlongsideTransition:nil completion:^(id<UIViewControllerTransitionCoordinatorContext>ctx){
        self.lastLandscape=landscape;
        [self updateSpreadVisibility];
        [self showPage];
    }];
}
- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView{return self.image;}
- (void)scrollViewDidZoom:(UIScrollView *)scrollView{
    CGRect frame=self.image.frame;
    CGSize bounds=scrollView.bounds.size;
    frame.origin.x=MAX(0,(bounds.width-frame.size.width)*.5);
    frame.origin.y=MAX(0,(bounds.height-frame.size.height)*.5);
    self.image.frame=frame;
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if(self.zoom.zoomScale<=1.01){
        self.image.frame=self.zoom.bounds;
        self.zoom.contentSize=self.zoom.bounds.size;
    }
}
- (void)zoomTap:(UITapGestureRecognizer *)gesture {
    if(self.zoom.zoomScale>1.05){[self.zoom setZoomScale:1 animated:YES];return;}
    CGPoint point=[gesture locationInView:self.image];
    CGRect frame=CGRectMake(point.x-70,point.y-70,140,140);
    [self.zoom zoomToRect:frame animated:YES];
}
- (void)pageTap:(UITapGestureRecognizer *)gesture {
    if(self.zoom.zoomScale>1.05)return;
    CGPoint point=[gesture locationInView:self.view];
    CGFloat x=point.x/MAX(1,self.view.bounds.size.width);
    if(x<.23)[self previousPage];
    else if(x>.77)[self nextPage];
    else {
        self.chromeHidden=!self.chromeHidden;
        self.topChrome.hidden=self.chromeHidden;
        self.bottomChrome.hidden=self.chromeHidden;
    }
}
- (void)scrubChanged:(UISlider *)slider {
    self.page=(NSInteger)lround(slider.value);
    [self showPage];
}
- (void)nextPage {
    if(self.zoom.zoomScale>1.01)return;
    NSInteger count=[(NSArray *)self.issue[@"pages"] count];
    NSInteger step=[self usingTwoPage] && self.page>0?2:1;
    NSInteger candidate=self.page+step;
    if(candidate<count){self.page=candidate;[self showPage];}
    else [self showBookEnd];
}
- (void)previousPage {
    if(self.zoom.zoomScale>1.01)return;
    if(self.page<=0)return;
    NSInteger step=[self usingTwoPage] && self.page>1?2:1;
    self.page=MAX(0,self.page-step);[self showPage];
}
static void PGDrawImageFitted(UIImage *image,CGRect slot){
    if(!image)return;
    CGFloat x=slot.size.width/MAX(image.size.width,1);
    CGFloat y=slot.size.height/MAX(image.size.height,1);
    CGFloat scale=MIN(x,y);
    CGSize size=CGSizeMake(image.size.width*scale,image.size.height*scale);
    CGRect dest=CGRectMake(CGRectGetMidX(slot)-size.width/2,CGRectGetMidY(slot)-size.height/2,size.width,size.height);
    [image drawInRect:dest];
}
- (void)showPage{
    NSArray *pages=self.issue[@"pages"];if(!pages.count)return;
    self.page=MAX(0,MIN(self.page,(NSInteger)pages.count-1));
    BOOL spread=[self usingTwoPage]&&self.page>0;
    if(spread)self.page=1+((self.page-1)/2)*2;
    self.zoom.zoomScale=1;
    if(spread){
        NSInteger second=self.page+1;
        UIImage *left=PGImage(pages[self.page]);
        UIImage *right=second<(NSInteger)pages.count?PGImage(pages[second]):nil;
        CGSize canvasSize=CGSizeMake(2048,1536);
        UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];
        format.scale=1;format.opaque=YES;
        UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc]initWithSize:canvasSize format:format];
        self.image.image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){
            [[UIColor colorWithWhite:.07 alpha:1] setFill];
            UIRectFill(CGRectMake(0,0,canvasSize.width,canvasSize.height));
            PGDrawImageFitted(left,CGRectMake(10,9,1007,1518));
            PGDrawImageFitted(right,CGRectMake(1031,9,1007,1518));
            [[UIColor colorWithWhite:.28 alpha:1] setFill];
            UIRectFill(CGRectMake(1021,0,6,canvasSize.height));
        }];
        self.counter.text=second<(NSInteger)pages.count?
         [NSString stringWithFormat:@"%ld–%ld / %lu",(long)self.page+1,(long)second+1,(unsigned long)pages.count]:
         [NSString stringWithFormat:@"%ld / %lu",(long)self.page+1,(unsigned long)pages.count];
    } else {
        self.image.image=PGImage(pages[self.page]);
        self.counter.text=[NSString stringWithFormat:@"%ld / %lu",(long)self.page+1,(unsigned long)pages.count];
    }
    self.image.accessibilityLabel=[NSString stringWithFormat:@"%@ page %ld",self.issue[@"title"],(long)self.page+1];
    [self updateBookmarkAppearance];
    self.scrubber.maximumValue=(float)MAX(0,(NSInteger)pages.count-1);
    [self.scrubber setValue:(float)self.page animated:NO];
    [[NSUserDefaults standardUserDefaults] setInteger:self.page forKey:[@"native-progress-" stringByAppendingString:self.issue[@"id"]]];
    [[NSUserDefaults standardUserDefaults] setObject:self.issue[@"id"] forKey:@"native-last-issue"];
}
- (NSString *)bookmarkKey{
    return [@"native-bookmark-" stringByAppendingString:self.issue[@"id"]];
}
- (void)updateBookmarkAppearance{
    NSInteger saved=[[NSUserDefaults standardUserDefaults] integerForKey:[self bookmarkKey]];
    // Saved page numbers are one-based so 0 reliably represents no bookmark.
    BOOL marked=(saved==self.page+1);
    self.bookmarkButton.alpha=marked?1.0:.55;
    self.bookmarkButton.accessibilityLabel=marked?@"Remove page bookmark":@"Bookmark current page";
    self.bookmarkButton.accessibilityValue=marked?@"Saved":@"Not saved";
    self.bookmarkButton.accessibilityHint=@"Tap to save or remove this page. Press and hold to jump to a saved bookmark.";
}
- (void)jumpToBookmark:(UILongPressGestureRecognizer *)recognizer{
    if(recognizer.state!=UIGestureRecognizerStateBegan)return;
    NSInteger saved=[[NSUserDefaults standardUserDefaults] integerForKey:[self bookmarkKey]];
    if(saved>0 && saved<=(NSInteger)[(NSArray *)self.issue[@"pages"] count]){
        self.page=saved-1;[self showPage];
        UINotificationFeedbackGenerator *feedback=[UINotificationFeedbackGenerator new];
        [feedback notificationOccurred:UINotificationFeedbackTypeSuccess];
    }
}
- (void)toggleBookmark:(UIButton *)sender{
    NSUserDefaults *settings=[NSUserDefaults standardUserDefaults];
    NSString *key=[self bookmarkKey];
    if([settings integerForKey:key]==self.page+1)[settings removeObjectForKey:key];
    else [settings setInteger:self.page+1 forKey:key];
    [self updateBookmarkAppearance];
    UISelectionFeedbackGenerator *feedback=[UISelectionFeedbackGenerator new];
    [feedback selectionChanged];
}
- (void)closeBookEnd{
    [UIView animateWithDuration:.16 animations:^{self.endOverlay.alpha=0;} completion:^(BOOL done){
        [self.endOverlay removeFromSuperview];self.endOverlay=nil;
    }];
}
- (void)readNextIssue:(UIButton *)sender{
    NSArray *catalog=[self.issue[@"kind"] isEqual:@"custom"]?PGImportedLibrary():PGLibrary();
    NSUInteger found=[catalog indexOfObjectPassingTest:^BOOL(NSDictionary *item,NSUInteger idx,BOOL *stop){
        return [item[@"id"] isEqual:self.issue[@"id"]];
    }];
    if(found==NSNotFound || found+1>=catalog.count)return;
    [self.endOverlay removeFromSuperview];self.endOverlay=nil;
    self.issue=catalog[found+1];
    self.page=0;
    self.chromeHidden=NO;self.topChrome.hidden=NO;self.bottomChrome.hidden=NO;
    self.issueTitle.text=self.issue[@"title"];
    [self showPage];
}
- (void)finishBookEnd:(UIButton *)sender{
    [self.endOverlay removeFromSuperview];self.endOverlay=nil;
    [self close];
}
- (UIButton *)bookEndButton:(NSString *)title action:(SEL)action{
    UIButton *b=[UIButton buttonWithType:UIButtonTypeSystem];
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    b.titleLabel.font=[UIFont boldSystemFontOfSize:15];
    [b setBackgroundImage:PGImage(@"assets/ipa_original/blue_button.png") forState:UIControlStateNormal];
    b.layer.cornerRadius=6;b.clipsToBounds=YES;
    [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    b.translatesAutoresizingMaskIntoConstraints=NO;[b.heightAnchor constraintEqualToConstant:38].active=YES;
    return b;
}
- (void)showBookEnd{
    if(self.endOverlay)return;
    NSArray *catalog=[self.issue[@"kind"] isEqual:@"custom"]?PGImportedLibrary():PGLibrary();
    NSUInteger index=[catalog indexOfObjectPassingTest:^BOOL(NSDictionary *item,NSUInteger n,BOOL *stop){
        return [item[@"id"] isEqual:self.issue[@"id"]];
    }];
    NSDictionary *next=(index!=NSNotFound && index+1<catalog.count)?catalog[index+1]:nil;
    UIView *overlay=[UIView new];overlay.frame=self.view.bounds;
    overlay.autoresizingMask=UIViewAutoresizingFlexibleWidth|UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor=[UIColor colorWithWhite:0 alpha:.95];
    self.endOverlay=overlay;[self.view addSubview:overlay];
    UIView *panel=[UIView new];panel.translatesAutoresizingMaskIntoConstraints=NO;
    panel.backgroundColor=[UIColor colorWithRed:.07 green:.26 blue:.32 alpha:1];
    panel.layer.cornerRadius=12;panel.layer.borderWidth=2;
    panel.layer.borderColor=[UIColor colorWithRed:.42 green:.68 blue:.59 alpha:1].CGColor;
    [overlay addSubview:panel];
    UILabel *heading=[UILabel new];heading.translatesAutoresizingMaskIntoConstraints=NO;
    heading.text=@"End of Issue";heading.textColor=UIColor.whiteColor;
    heading.font=[UIFont boldSystemFontOfSize:23];heading.textAlignment=NSTextAlignmentCenter;
    [panel addSubview:heading];
    UILabel *subtitle=[UILabel new];subtitle.translatesAutoresizingMaskIntoConstraints=NO;
    subtitle.text=next?@"Continue reading":@"You've completed the collection!";
    subtitle.textColor=[UIColor colorWithRed:.86 green:.94 blue:.92 alpha:1];
    subtitle.textAlignment=NSTextAlignmentCenter;subtitle.font=[UIFont systemFontOfSize:14];
    [panel addSubview:subtitle];
    UIImageView *cover=[UIImageView new];cover.translatesAutoresizingMaskIntoConstraints=NO;
    cover.contentMode=UIViewContentModeScaleAspectFit;
    cover.image=next?PGImage(next[@"thumbnail"]?:next[@"cover"]):PGImage(self.issue[@"thumbnail"]?:self.issue[@"cover"]);
    cover.layer.shadowColor=UIColor.blackColor.CGColor;cover.layer.shadowOpacity=.6;
    [panel addSubview:cover];
    UILabel *nextTitle=[UILabel new];nextTitle.translatesAutoresizingMaskIntoConstraints=NO;
    nextTitle.numberOfLines=2;nextTitle.textAlignment=NSTextAlignmentCenter;
    nextTitle.text=next?next[@"title"]:([self.issue[@"kind"] isEqual:@"custom"]?@"End of imported collection":@"All 25 original issues read");
    nextTitle.textColor=UIColor.whiteColor;nextTitle.font=[UIFont boldSystemFontOfSize:13];
    [panel addSubview:nextTitle];
    UIButton *read=[self bookEndButton:@"Read Next Issue" action:@selector(readNextIssue:)];
    if(next)[panel addSubview:read];
    UIButton *library=[self bookEndButton:@"Return to My Comics" action:@selector(finishBookEnd:)];
    [panel addSubview:library];
    UIButton *stay=[UIButton buttonWithType:UIButtonTypeSystem];
    stay.translatesAutoresizingMaskIntoConstraints=NO;
    [stay setTitle:@"Stay on this page" forState:UIControlStateNormal];
    [stay setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    [stay addTarget:self action:@selector(closeBookEnd) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:stay];
    NSMutableArray *rules=[NSMutableArray arrayWithArray:@[
      [panel.centerXAnchor constraintEqualToAnchor:overlay.centerXAnchor],
      [panel.centerYAnchor constraintEqualToAnchor:overlay.centerYAnchor],
      [panel.widthAnchor constraintEqualToConstant:MIN(420,CGRectGetWidth(self.view.bounds)*.84)],
      [panel.heightAnchor constraintLessThanOrEqualToAnchor:overlay.heightAnchor constant:-16],
      [heading.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:12],
      [heading.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-12],
      [heading.topAnchor constraintEqualToAnchor:panel.topAnchor constant:11],
      [heading.heightAnchor constraintEqualToConstant:32],
      [subtitle.topAnchor constraintEqualToAnchor:heading.bottomAnchor constant:1],
      [subtitle.centerXAnchor constraintEqualToAnchor:panel.centerXAnchor],
      [cover.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:8],
      [cover.centerXAnchor constraintEqualToAnchor:panel.centerXAnchor],
      [cover.heightAnchor constraintEqualToConstant:126],
      [cover.widthAnchor constraintEqualToConstant:88],
      [nextTitle.topAnchor constraintEqualToAnchor:cover.bottomAnchor constant:6],
      [nextTitle.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:10],
      [nextTitle.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-10],
      [nextTitle.heightAnchor constraintEqualToConstant:36],
      [library.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16],
      [library.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16],
      [stay.topAnchor constraintEqualToAnchor:library.bottomAnchor constant:5],
      [stay.centerXAnchor constraintEqualToAnchor:panel.centerXAnchor],
      [stay.heightAnchor constraintEqualToConstant:28],
      [stay.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-8]
    ]];
    if(next){
        [rules addObjectsFromArray:@[
            [read.topAnchor constraintEqualToAnchor:nextTitle.bottomAnchor constant:7],
            [read.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:16],
            [read.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-16],
            [library.topAnchor constraintEqualToAnchor:read.bottomAnchor constant:6]
        ]];
    }else{
        [rules addObject:[library.topAnchor constraintEqualToAnchor:nextTitle.bottomAnchor constant:7]];
    }
    [NSLayoutConstraint activateConstraints:rules];
}
- (void)close{[self dismissViewControllerAnimated:YES completion:nil];}
- (BOOL)prefersStatusBarHidden{return YES;}
@end

@interface PGShelfBackdrop : UIView
@property(nonatomic,strong) UIImage *first;
@property(nonatomic,strong) UIImage *second;
@property(nonatomic,assign) CGFloat rowHeight;
@property(nonatomic,assign) NSInteger rows;
@end
@implementation PGShelfBackdrop
- (void)drawRect:(CGRect)rect {
 if(self.rowHeight<=0)return;
 NSInteger begin=MAX(0,(NSInteger)floor(CGRectGetMinY(rect)/self.rowHeight));
 NSInteger end=MIN(self.rows,(NSInteger)ceil(CGRectGetMaxY(rect)/self.rowHeight)+1);
 for(NSInteger n=begin;n<end;n++){
  UIImage *image=(n%2==0)?self.first:self.second;
  [image drawInRect:CGRectMake(0,n*self.rowHeight,self.bounds.size.width,self.rowHeight)];
 }
}
@end

@interface PGCoverCell : UICollectionViewCell
@property(nonatomic,strong) UIImageView *cover;
@property(nonatomic,strong) UILabel *title;
@end
@implementation PGCoverCell
- (instancetype)initWithFrame:(CGRect)rect {
 if((self=[super initWithFrame:rect])){
  self.backgroundColor=UIColor.clearColor;
  _cover=[UIImageView new];_cover.translatesAutoresizingMaskIntoConstraints=NO;
  _cover.contentMode=UIViewContentModeScaleAspectFill;_cover.clipsToBounds=YES;
  _cover.layer.borderColor=[UIColor colorWithRed:.035 green:.22 blue:.35 alpha:1].CGColor;
  _cover.layer.borderWidth=4;_cover.layer.shadowColor=UIColor.blackColor.CGColor;
  _title=[UILabel new];_title.translatesAutoresizingMaskIntoConstraints=NO;
  _title.textAlignment=NSTextAlignmentCenter;_title.numberOfLines=2;_title.lineBreakMode=NSLineBreakByTruncatingTail;
  _title.font=[UIFont boldSystemFontOfSize:13];_title.textColor=UIColor.whiteColor;
  _title.shadowColor=UIColor.blackColor;_title.shadowOffset=CGSizeMake(0,2);
  [self.contentView addSubview:_cover];[self.contentView addSubview:_title];
  [NSLayoutConstraint activateConstraints:@[
   [_cover.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:13],
   [_cover.centerXAnchor constraintEqualToAnchor:self.contentView.centerXAnchor],
   [_cover.widthAnchor constraintLessThanOrEqualToAnchor:self.contentView.widthAnchor multiplier:.73],
   [_cover.widthAnchor constraintLessThanOrEqualToConstant:215],
   [_cover.heightAnchor constraintEqualToAnchor:self.contentView.heightAnchor multiplier:.755],
   [_cover.widthAnchor constraintEqualToAnchor:_cover.heightAnchor multiplier:.68],
   [_title.topAnchor constraintEqualToAnchor:_cover.bottomAnchor constant:9],
   [_title.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:5],
   [_title.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-5],
   [_title.heightAnchor constraintLessThanOrEqualToConstant:40]]];
 }
 return self;
}
- (void)prepareForReuse{[super prepareForReuse];self.cover.image=nil;self.title.text=nil;}
@end

@interface PGListCell : UICollectionViewCell
@property(nonatomic,strong) UIImageView *thumbnail;
@property(nonatomic,strong) UILabel *headline;
@property(nonatomic,strong) UILabel *subtitle;
@end
@implementation PGListCell
- (instancetype)initWithFrame:(CGRect)rect {
 if((self=[super initWithFrame:rect])){
  self.backgroundColor=[UIColor colorWithRed:.09 green:.35 blue:.44 alpha:.84];
  _thumbnail=[UIImageView new];_thumbnail.contentMode=UIViewContentModeScaleAspectFit;_thumbnail.clipsToBounds=YES;
  _headline=[UILabel new];_headline.numberOfLines=2;_headline.textColor=UIColor.whiteColor;_headline.font=[UIFont boldSystemFontOfSize:14];
  _subtitle=[UILabel new];_subtitle.textColor=[UIColor colorWithRed:.85 green:.94 blue:.91 alpha:1];_subtitle.font=[UIFont systemFontOfSize:11];
  [self.contentView addSubview:_thumbnail];[self.contentView addSubview:_headline];[self.contentView addSubview:_subtitle];
  UIView *line=[UIView new];line.backgroundColor=[UIColor colorWithWhite:1 alpha:.25];line.frame=CGRectMake(0,79,rect.size.width,1);
  line.autoresizingMask=UIViewAutoresizingFlexibleWidth;[self.contentView addSubview:line];
 }return self;
}
- (void)layoutSubviews {
 [super layoutSubviews];CGFloat w=self.contentView.bounds.size.width;
 self.thumbnail.frame=CGRectMake(12,6,47,67);
 self.headline.frame=CGRectMake(72,10,MAX(0,w-84),43);
 self.subtitle.frame=CGRectMake(72,54,MAX(0,w-84),18);
}
- (void)prepareForReuse{[super prepareForReuse];self.thumbnail.image=nil;self.headline.text=nil;}
@end

@interface PGLibraryController : UIViewController <UICollectionViewDataSource,UICollectionViewDelegateFlowLayout,UIScrollViewDelegate,UISearchBarDelegate,UIDocumentPickerDelegate>
@property(nonatomic,strong) NSArray *issues;
@property(nonatomic,strong) UICollectionView *collection;
@property(nonatomic,strong) PGShelfBackdrop *backdrop;
@property(nonatomic,strong) UIImageView *banner;
@property(nonatomic,strong) UIView *header;
@property(nonatomic,strong) UIView *tabs;
@property(nonatomic,strong) UILabel *headerLabel;
@property(nonatomic,strong) UIButton *comicsButton;
@property(nonatomic,strong) UIButton *customButton;
@property(nonatomic,strong) NSArray *visibleIssues;
@property(nonatomic,strong) UIView *toolsBar;
@property(nonatomic,strong) UISearchBar *searchBar;
@property(nonatomic,strong) UISegmentedControl *modeSelector;
@property(nonatomic,assign) BOOL listMode;
@property(nonatomic,assign) BOOL customMode;
@property(nonatomic,strong) UIButton *importButton;
@property(nonatomic,strong) NSArray *customIssues;
@property(nonatomic,strong) UILabel *emptyLabel;
@property(nonatomic,strong) UIButton *emptyImportButton;

@end
@implementation PGLibraryController
- (UIImageView *)art:(NSString *)path mode:(UIViewContentMode)mode {
 UIImageView *v=[[UIImageView alloc]initWithImage:PGImage(path)];v.contentMode=mode;v.clipsToBounds=YES;
 v.translatesAutoresizingMaskIntoConstraints=NO;return v;
}
- (void)viewDidLoad {
 [super viewDidLoad];self.issues=PGLibrary();self.customIssues=PGImportedLibrary();self.visibleIssues=self.issues;self.customMode=NO;
 self.view.backgroundColor=[UIColor colorWithRed:.18 green:.65 blue:.73 alpha:1];
 // The original iVerse iPad banner and drawer images are embedded in the recovered IPA.
 self.banner=[self art:@"assets/ipa_original/shelfBlueiPad@2x.png" mode:UIViewContentModeScaleToFill];
 [self.view addSubview:self.banner];
 UIImageView *logo=[self art:@"assets/ipa_original/native_header_logo.png" mode:UIViewContentModeScaleAspectFit];
 [self.banner addSubview:logo];
 self.header=[UIView new];self.header.translatesAutoresizingMaskIntoConstraints=NO;
 UIImageView *leaf=[self art:@"assets/ipa_original/drawer_bg@2x.png" mode:UIViewContentModeScaleToFill];
 [self.header addSubview:leaf];
 self.headerLabel=[UILabel new];self.headerLabel.translatesAutoresizingMaskIntoConstraints=NO;
 self.headerLabel.text=@"My Comics";self.headerLabel.textColor=UIColor.whiteColor;
 self.headerLabel.textAlignment=NSTextAlignmentCenter;
 self.headerLabel.font=[UIFont boldSystemFontOfSize:21];
 self.headerLabel.shadowColor=UIColor.blackColor;self.headerLabel.shadowOffset=CGSizeMake(0,2);
 [self.header addSubview:self.headerLabel];[self.view addSubview:self.header];
 self.toolsBar=[UIView new];self.toolsBar.translatesAutoresizingMaskIntoConstraints=NO;
 UIImageView *toolsArt=[self art:@"assets/ipa_original/drawer_bg@2x.png" mode:UIViewContentModeScaleToFill];
 [self.toolsBar addSubview:toolsArt];
 self.modeSelector=[[UISegmentedControl alloc]initWithItems:@[@"Shelf",@"List"]];
 self.modeSelector.translatesAutoresizingMaskIntoConstraints=NO;
 self.listMode=[[NSUserDefaults standardUserDefaults] boolForKey:@"native-list-mode"];
 self.modeSelector.selectedSegmentIndex=self.listMode?1:0;
 [self.modeSelector addTarget:self action:@selector(changeMode:) forControlEvents:UIControlEventValueChanged];
 [self.toolsBar addSubview:self.modeSelector];
 self.searchBar=[UISearchBar new];self.searchBar.translatesAutoresizingMaskIntoConstraints=NO;
 self.searchBar.searchBarStyle=UISearchBarStyleMinimal;self.searchBar.placeholder=@"Search comics";
 self.searchBar.delegate=self;
 self.searchBar.autocorrectionType=UITextAutocorrectionTypeNo;
 [self.toolsBar addSubview:self.searchBar];
 UIButton *downloads=[UIButton buttonWithType:UIButtonTypeSystem];downloads.translatesAutoresizingMaskIntoConstraints=NO;
 [downloads setImage:PGImage(@"assets/ipa_original/downloads.png") forState:UIControlStateNormal];
 downloads.tintColor=UIColor.whiteColor;downloads.accessibilityLabel=@"Downloads and imports";
 [downloads addTarget:self action:@selector(importFromFiles) forControlEvents:UIControlEventTouchUpInside];
 self.importButton=downloads;
 [self.toolsBar addSubview:downloads];
 UIButton *settings=[UIButton buttonWithType:UIButtonTypeSystem];settings.translatesAutoresizingMaskIntoConstraints=NO;
 [settings setImage:PGImage(@"assets/ipa_original/settings@2x.png") forState:UIControlStateNormal];
 settings.tintColor=UIColor.whiteColor;settings.accessibilityLabel=@"Settings";
 [settings addTarget:self action:@selector(showSettings) forControlEvents:UIControlEventTouchUpInside];
 [self.toolsBar addSubview:settings];
 [self.view addSubview:self.toolsBar];
 [NSLayoutConstraint activateConstraints:@[
   [self.toolsBar.topAnchor constraintEqualToAnchor:self.header.bottomAnchor],
   [self.toolsBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
   [self.toolsBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
   [self.toolsBar.heightAnchor constraintEqualToConstant:43],
   [toolsArt.topAnchor constraintEqualToAnchor:self.toolsBar.topAnchor],
   [toolsArt.bottomAnchor constraintEqualToAnchor:self.toolsBar.bottomAnchor],
   [toolsArt.leadingAnchor constraintEqualToAnchor:self.toolsBar.leadingAnchor],
   [toolsArt.trailingAnchor constraintEqualToAnchor:self.toolsBar.trailingAnchor],
   [self.modeSelector.leadingAnchor constraintEqualToAnchor:self.toolsBar.leadingAnchor constant:8],
   [self.modeSelector.centerYAnchor constraintEqualToAnchor:self.toolsBar.centerYAnchor],
   [self.modeSelector.widthAnchor constraintEqualToConstant:124],
   [self.searchBar.leadingAnchor constraintEqualToAnchor:self.modeSelector.trailingAnchor constant:4],
   [self.searchBar.trailingAnchor constraintEqualToAnchor:downloads.leadingAnchor constant:0],
   [self.searchBar.topAnchor constraintEqualToAnchor:self.toolsBar.topAnchor],
   [self.searchBar.bottomAnchor constraintEqualToAnchor:self.toolsBar.bottomAnchor],
   [downloads.trailingAnchor constraintEqualToAnchor:settings.leadingAnchor constant:-3],
   [downloads.widthAnchor constraintEqualToConstant:36],
   [downloads.centerYAnchor constraintEqualToAnchor:self.toolsBar.centerYAnchor],
   [downloads.heightAnchor constraintEqualToConstant:38],
   [settings.trailingAnchor constraintEqualToAnchor:self.toolsBar.trailingAnchor constant:-6],
   [settings.widthAnchor constraintEqualToConstant:36],
   [settings.heightAnchor constraintEqualToConstant:38],
   [settings.centerYAnchor constraintEqualToAnchor:self.toolsBar.centerYAnchor]]];
 UICollectionViewFlowLayout *flow=[UICollectionViewFlowLayout new];
 flow.minimumLineSpacing=0;flow.minimumInteritemSpacing=0;flow.sectionInset=UIEdgeInsetsZero;
 self.collection=[[UICollectionView alloc]initWithFrame:CGRectZero collectionViewLayout:flow];
 self.collection.translatesAutoresizingMaskIntoConstraints=NO;
 self.collection.backgroundColor=[UIColor colorWithRed:.20 green:.68 blue:.77 alpha:1];
 self.collection.alwaysBounceVertical=YES;self.collection.dataSource=self;
 self.collection.delegate=self;self.collection.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;
 [self.collection registerClass:PGCoverCell.class forCellWithReuseIdentifier:@"cover"];
 [self.collection registerClass:PGListCell.class forCellWithReuseIdentifier:@"list"];
 UILongPressGestureRecognizer *removeGesture=[[UILongPressGestureRecognizer alloc]initWithTarget:self action:@selector(longPressComic:)];
 removeGesture.minimumPressDuration=.65;
 [self.collection addGestureRecognizer:removeGesture];
 self.backdrop=[PGShelfBackdrop new];self.backdrop.userInteractionEnabled=NO;
 [self.collection addSubview:self.backdrop];[self.collection sendSubviewToBack:self.backdrop];
 [self.view addSubview:self.collection];
 self.emptyLabel=[UILabel new];
 self.emptyLabel.translatesAutoresizingMaskIntoConstraints=NO;
 self.emptyLabel.text=@"No custom comics yet\nImport a CBZ from Files to get started.";
 self.emptyLabel.textAlignment=NSTextAlignmentCenter;
 self.emptyLabel.numberOfLines=3;
 self.emptyLabel.textColor=UIColor.whiteColor;
 self.emptyLabel.font=[UIFont boldSystemFontOfSize:17];
 self.emptyLabel.hidden=YES;
 [self.view addSubview:self.emptyLabel];
 self.emptyImportButton=[UIButton buttonWithType:UIButtonTypeSystem];
 self.emptyImportButton.translatesAutoresizingMaskIntoConstraints=NO;
 [self.emptyImportButton setTitle:@"Import CBZ" forState:UIControlStateNormal];
 [self.emptyImportButton setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
 [self.emptyImportButton setBackgroundImage:PGImage(@"assets/ipa_original/blue_button.png") forState:UIControlStateNormal];
 [self.emptyImportButton addTarget:self action:@selector(importFromFiles) forControlEvents:UIControlEventTouchUpInside];
 self.emptyImportButton.hidden=YES;
 [self.view addSubview:self.emptyImportButton];
 self.tabs=[UIView new];self.tabs.translatesAutoresizingMaskIntoConstraints=NO;self.tabs.backgroundColor=[UIColor colorWithRed:.07 green:.29 blue:.35 alpha:1];
 UIImageView *tabsTexture=[self art:@"assets/ipa_original/drawer_bg@2x.png" mode:UIViewContentModeScaleToFill];
 [self.tabs addSubview:tabsTexture];
 self.comicsButton=[self tabButton:@"My Comics" icon:@"assets/ipa_original/my_comics@2x.png" action:@selector(showComics)];
 self.customButton=[self tabButton:@"Custom" icon:@"assets/ipa_original/list_icon@2x.png" action:@selector(showCustom)];
 [self.tabs addSubview:self.comicsButton];[self.tabs addSubview:self.customButton];
 [self.view addSubview:self.tabs];
 [NSLayoutConstraint activateConstraints:@[
  [self.banner.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
  [self.banner.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[self.banner.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
  [self.banner.heightAnchor constraintEqualToConstant:UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad?112:95],
  [logo.centerXAnchor constraintEqualToAnchor:self.banner.centerXAnchor],[logo.centerYAnchor constraintEqualToAnchor:self.banner.centerYAnchor],
  [logo.widthAnchor constraintEqualToConstant:320],[logo.heightAnchor constraintEqualToAnchor:self.banner.heightAnchor],
  [self.header.topAnchor constraintEqualToAnchor:self.banner.bottomAnchor],
  [self.header.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[self.header.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
  [self.header.heightAnchor constraintEqualToConstant:47],
  [leaf.topAnchor constraintEqualToAnchor:self.header.topAnchor],[leaf.bottomAnchor constraintEqualToAnchor:self.header.bottomAnchor],
  [leaf.leadingAnchor constraintEqualToAnchor:self.header.leadingAnchor],[leaf.trailingAnchor constraintEqualToAnchor:self.header.trailingAnchor],
  [self.headerLabel.centerXAnchor constraintEqualToAnchor:self.header.centerXAnchor],[self.headerLabel.centerYAnchor constraintEqualToAnchor:self.header.centerYAnchor],
  [self.emptyLabel.centerXAnchor constraintEqualToAnchor:self.collection.centerXAnchor],
  [self.emptyLabel.centerYAnchor constraintEqualToAnchor:self.collection.centerYAnchor constant:-30],
  [self.emptyLabel.widthAnchor constraintLessThanOrEqualToAnchor:self.collection.widthAnchor constant:-25],
  [self.emptyImportButton.centerXAnchor constraintEqualToAnchor:self.collection.centerXAnchor],
  [self.emptyImportButton.topAnchor constraintEqualToAnchor:self.emptyLabel.bottomAnchor constant:14],
  [self.emptyImportButton.widthAnchor constraintEqualToConstant:172],
  [self.emptyImportButton.heightAnchor constraintEqualToConstant:43],
  [self.collection.topAnchor constraintEqualToAnchor:self.toolsBar.bottomAnchor],
  [self.collection.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
  [self.collection.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
  [self.collection.bottomAnchor constraintEqualToAnchor:self.tabs.topAnchor],
  [self.tabs.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
  [self.tabs.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
  [self.tabs.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
  [self.tabs.heightAnchor constraintEqualToConstant:58+self.view.safeAreaInsets.bottom],
  [tabsTexture.topAnchor constraintEqualToAnchor:self.tabs.topAnchor],[tabsTexture.bottomAnchor constraintEqualToAnchor:self.tabs.bottomAnchor],
  [tabsTexture.leadingAnchor constraintEqualToAnchor:self.tabs.leadingAnchor],[tabsTexture.trailingAnchor constraintEqualToAnchor:self.tabs.trailingAnchor],
  [self.comicsButton.topAnchor constraintEqualToAnchor:self.tabs.topAnchor constant:3],
  [self.comicsButton.leadingAnchor constraintEqualToAnchor:self.tabs.leadingAnchor constant:4],
  [self.comicsButton.bottomAnchor constraintEqualToAnchor:self.tabs.safeAreaLayoutGuide.bottomAnchor constant:-3],
  [self.comicsButton.widthAnchor constraintEqualToAnchor:self.tabs.widthAnchor multiplier:.5 constant:-6],
  [self.customButton.topAnchor constraintEqualToAnchor:self.comicsButton.topAnchor],
  [self.customButton.leadingAnchor constraintEqualToAnchor:self.comicsButton.trailingAnchor constant:4],
  [self.customButton.trailingAnchor constraintEqualToAnchor:self.tabs.trailingAnchor constant:-4],
  [self.customButton.bottomAnchor constraintEqualToAnchor:self.comicsButton.bottomAnchor]]];
 [self showComics];
}
- (UIButton *)tabButton:(NSString *)title icon:(NSString *)icon action:(SEL)action {
 UIButton *button=[UIButton buttonWithType:UIButtonTypeCustom];
 button.translatesAutoresizingMaskIntoConstraints=NO;button.layer.cornerRadius=5;button.clipsToBounds=YES;
 UIImageView *symbol=[self art:icon mode:UIViewContentModeScaleAspectFit];
 UILabel *label=[UILabel new];label.translatesAutoresizingMaskIntoConstraints=NO;label.text=title;
 label.textColor=UIColor.whiteColor;label.font=[UIFont boldSystemFontOfSize:12];label.textAlignment=NSTextAlignmentCenter;
 label.shadowColor=UIColor.blackColor;label.shadowOffset=CGSizeMake(0,1);
 [button addSubview:symbol];[button addSubview:label];
 [NSLayoutConstraint activateConstraints:@[
  [symbol.topAnchor constraintEqualToAnchor:button.topAnchor constant:2],
  [symbol.centerXAnchor constraintEqualToAnchor:button.centerXAnchor],
  [symbol.widthAnchor constraintEqualToConstant:27],[symbol.heightAnchor constraintEqualToConstant:27],
  [label.topAnchor constraintEqualToAnchor:symbol.bottomAnchor constant:0],
  [label.leadingAnchor constraintEqualToAnchor:button.leadingAnchor],
  [label.trailingAnchor constraintEqualToAnchor:button.trailingAnchor],
  [label.heightAnchor constraintEqualToConstant:16]]];
 [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];return button;
}
- (void)refreshVisibleIssues {
    NSArray *base=self.customMode?self.customIssues:self.issues;
    NSString *query=self.searchBar.text?:@"";
    if(query.length){
        base=[base filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *item,NSDictionary *bindings){
            return [[item[@"title"] description] rangeOfString:query options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location!=NSNotFound;
        }]];
    }
    self.visibleIssues=base;
    BOOL empty=self.customMode && !self.customIssues.count;
    self.emptyLabel.hidden=!empty;
    self.emptyImportButton.hidden=!empty;
    [self.collection.collectionViewLayout invalidateLayout];
    [self.collection reloadData];
    [self.collection setContentOffset:CGPointZero animated:NO];
    [self viewDidLayoutSubviews];
}
- (void)showComics{
    self.customMode=NO;self.headerLabel.text=@"My Comics";
    [self.comicsButton setBackgroundImage:PGImage(@"assets/ipa_original/blue_button.png") forState:UIControlStateNormal];
    [self.customButton setBackgroundImage:nil forState:UIControlStateNormal];
    self.importButton.alpha=.65;
    [self refreshVisibleIssues];
}
- (void)showCustom{
    self.customMode=YES;self.headerLabel.text=@"Custom Comics";
    [self.customButton setBackgroundImage:PGImage(@"assets/ipa_original/blue_button.png") forState:UIControlStateNormal];
    [self.comicsButton setBackgroundImage:nil forState:UIControlStateNormal];
    self.importButton.alpha=1;
    self.customIssues=PGImportedLibrary();
    [self refreshVisibleIssues];

}
- (void)importFromFiles{
    [self.searchBar resignFirstResponder];
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc]
      initWithDocumentTypes:@[@"public.data",@"com.pkware.zip-archive"] inMode:UIDocumentPickerModeImport];
    picker.delegate=self;
    picker.modalPresentationStyle=UIModalPresentationFormSheet;
    [self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)picker didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls{
    NSURL *url=urls.firstObject;
    if(!url)return;
    NSString *ext=url.pathExtension.lowercaseString;
    if(![ext isEqualToString:@"cbz"] && ![ext isEqualToString:@"zip"]){
        [self showImportError:[NSError errorWithDomain:@"PocketGodComics" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Please choose a CBZ comic archive."}]];
        return;
    }
    self.headerLabel.text=@"Importing comic…";
    self.importButton.enabled=NO;
    BOOL scoped=[url startAccessingSecurityScopedResource];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSError *error=nil;
        NSDictionary *book=PGImportComicCBZ(url,&error);
        if(scoped)[url stopAccessingSecurityScopedResource];
        dispatch_async(dispatch_get_main_queue(),^{
            self.importButton.enabled=YES;
            self.headerLabel.text=self.customMode?@"Custom Comics":@"My Comics";
            if(book){self.customMode=YES;self.searchBar.text=@"";[self showCustom];}
            else [self showImportError:error];
        });
    });
}
- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)picker{
    self.headerLabel.text=self.customMode?@"Custom Comics":@"My Comics";
}
- (void)importDocumentURL:(NSURL *)url{
    if(url)[self documentPicker:nil didPickDocumentsAtURLs:@[url]];
}
- (void)showImportError:(NSError *)error{
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Unable to Import"
      message:error.localizedDescription?:@"The selected file cannot be opened."
      preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)longPressComic:(UILongPressGestureRecognizer *)gesture {
    if(!self.customMode || gesture.state!=UIGestureRecognizerStateBegan)return;
    NSIndexPath *index=[self.collection indexPathForItemAtPoint:[gesture locationInView:self.collection]];
    if(!index || index.item>=self.visibleIssues.count)return;
    NSDictionary *book=self.visibleIssues[index.item];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Remove Imported Comic?"
      message:[NSString stringWithFormat:@"%@\n\nThis removes the imported comic and its reading progress.",book[@"title"]]
      preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Remove" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
        NSError *error=nil;
        if(PGRemoveImportedComic(book[@"id"],&error)){
            self.customIssues=PGImportedLibrary();
            [self refreshVisibleIssues];
        }else [self showImportError:error];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)changeMode:(UISegmentedControl *)selector {
 self.listMode=selector.selectedSegmentIndex==1;
 [[NSUserDefaults standardUserDefaults] setBool:self.listMode forKey:@"native-list-mode"];
 [self.collection.collectionViewLayout invalidateLayout];
 [self.collection reloadData];
 [self.collection setContentOffset:CGPointZero animated:NO];
 [self viewDidLayoutSubviews];
}
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)query {
 [self refreshVisibleIssues];
}
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {[searchBar resignFirstResponder];}
- (void)resumeLastIssue{
    NSString *last=[[NSUserDefaults standardUserDefaults] stringForKey:@"native-last-issue"];
    if(!last.length)return;
    for(NSDictionary *issue in [self.issues arrayByAddingObjectsFromArray:PGImportedLibrary()]){
        if([issue[@"id"] isEqualToString:last]){
            PGPageController *reader=[[PGPageController alloc]initWithIssue:issue];
            reader.modalPresentationStyle=UIModalPresentationFullScreen;
            [self presentViewController:reader animated:YES completion:nil];
            return;
        }
    }
}
- (void)showSettings {
 UIAlertController *menu=[UIAlertController alertControllerWithTitle:@"Pocket God Comics"
 message:[NSString stringWithFormat:@"Pocket God Comics 3.0\n25 original issues • %lu imported comics\nYour library and reading progress stay on this device.",(unsigned long)[PGImportedLibrary() count]]
 preferredStyle:UIAlertControllerStyleActionSheet];
 if([[NSUserDefaults standardUserDefaults] stringForKey:@"native-last-issue"].length)
 [menu addAction:[UIAlertAction actionWithTitle:@"Continue reading" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
    [self resumeLastIssue];
 }]];
 if(self.customMode){
 [menu addAction:[UIAlertAction actionWithTitle:@"Import a CBZ…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){[self importFromFiles];}]];
 if(self.customIssues.count){
 [menu addAction:[UIAlertAction actionWithTitle:@"Manage Imported Comics" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){
    UIAlertController *help=[UIAlertController alertControllerWithTitle:@"Custom Comics"
      message:@"Press and hold a custom comic cover to remove it. Original issues are always preserved."
      preferredStyle:UIAlertControllerStyleAlert];
    [help addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:help animated:YES completion:nil];
 }]];
 }
 }
 [menu addAction:[UIAlertAction actionWithTitle:@"Reset reading progress" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){
    UIAlertController *confirm=[UIAlertController alertControllerWithTitle:@"Reset progress?" message:@"This clears saved page positions for all original and imported comics. Bookmarks are kept." preferredStyle:UIAlertControllerStyleAlert];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"Reset" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){
      for(NSDictionary *issue in [self.issues arrayByAddingObjectsFromArray:PGImportedLibrary()])
          [[NSUserDefaults standardUserDefaults] removeObjectForKey:[@"native-progress-" stringByAppendingString:issue[@"id"]]];
      [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"native-last-issue"];
    }]];
    [self presentViewController:confirm animated:YES completion:nil];
 }]];
 [menu addAction:[UIAlertAction actionWithTitle:@"Close" style:UIAlertActionStyleCancel handler:nil]];
 UIPopoverPresentationController *pop=menu.popoverPresentationController;
 if(pop){pop.sourceView=self.toolsBar;pop.sourceRect=CGRectMake(self.toolsBar.bounds.size.width-44,0,42,42);}
 [self presentViewController:menu animated:YES completion:nil];
}
- (CGFloat)rowHeight{
 if(self.listMode)return 80;
 BOOL pad=UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad;
 if(!pad)return 206;
 return self.view.bounds.size.width>self.view.bounds.size.height?315:355;
}
- (NSInteger)columns{
 if(self.listMode)return 1;
 BOOL pad=UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad;
 return (pad&&self.view.bounds.size.width>self.view.bounds.size.height)?4:2;
}
- (void)viewDidLayoutSubviews{
 [super viewDidLayoutSubviews];
 NSInteger columns=[self columns];CGFloat row=[self rowHeight];
 NSInteger rows=(self.visibleIssues.count+columns-1)/columns;
 NSString *kind=UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad?
 (columns==4?@"ipad_landscape":@"ipad_portrait"):@"phone";
 NSString *one=[NSString stringWithFormat:@"assets/ipa_original/native_shelf_%@_0.png",kind];
 NSString *two=[NSString stringWithFormat:@"assets/ipa_original/native_shelf_%@_1.png",kind];
 if(![self.backdrop.accessibilityIdentifier isEqualToString:kind]){
  self.backdrop.first=PGImage(one);self.backdrop.second=PGImage(two);
  self.backdrop.accessibilityIdentifier=kind;
 }
 self.backdrop.hidden=self.listMode;
 self.collection.backgroundColor=self.listMode?[UIColor colorWithRed:.10 green:.40 blue:.48 alpha:1]:[UIColor colorWithRed:.20 green:.68 blue:.77 alpha:1];
 self.backdrop.rowHeight=row;self.backdrop.rows=rows;
 self.backdrop.frame=CGRectMake(0,0,self.collection.bounds.size.width,rows*row);
 [self.backdrop setNeedsDisplay];[self.collection sendSubviewToBack:self.backdrop];
}
- (NSInteger)collectionView:(UICollectionView *)c numberOfItemsInSection:(NSInteger)s{return self.visibleIssues.count;}
- (UICollectionViewCell *)collectionView:(UICollectionView *)c cellForItemAtIndexPath:(NSIndexPath *)index{
 NSDictionary *book=self.visibleIssues[index.item];
 if(self.listMode){
  PGListCell *cell=[c dequeueReusableCellWithReuseIdentifier:@"list" forIndexPath:index];
  cell.thumbnail.image=PGImage(book[@"thumbnail"]?:book[@"cover"]);cell.headline.text=book[@"title"];
  cell.subtitle.text=[NSString stringWithFormat:@"%lu pages",(unsigned long)[(NSArray *)book[@"pages"] count]];
  return cell;
 }
 PGCoverCell *cell=[c dequeueReusableCellWithReuseIdentifier:@"cover" forIndexPath:index];
 cell.cover.image=PGImage(book[@"thumbnail"]?:book[@"cover"]);cell.title.text=book[@"title"];
 cell.title.font=[UIFont boldSystemFontOfSize:UI_USER_INTERFACE_IDIOM()==UIUserInterfaceIdiomPad?13:10];
 return cell;
}
- (CGSize)collectionView:(UICollectionView *)c layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)index{
 return CGSizeMake(floor(c.bounds.size.width/[self columns]),[self rowHeight]);
}
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator{
 [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
 [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext>ctx){
  [self.collection.collectionViewLayout invalidateLayout];[self.collection setNeedsLayout];
 } completion:^(id<UIViewControllerTransitionCoordinatorContext>ctx){
  [self.collection.collectionViewLayout invalidateLayout];[self viewDidLayoutSubviews];
 }];
}
- (void)collectionView:(UICollectionView *)c didSelectItemAtIndexPath:(NSIndexPath *)index{
 [self.searchBar resignFirstResponder];
 PGPageController *reader=[[PGPageController alloc]initWithIssue:self.visibleIssues[index.item]];
 reader.modalPresentationStyle=UIModalPresentationFullScreen;[self presentViewController:reader animated:YES completion:nil];
}
@end
@implementation AppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)opts{
 self.window=[[UIWindow alloc]initWithFrame:UIScreen.mainScreen.bounds];
 self.window.rootViewController=[PGLibraryController new];[self.window makeKeyAndVisible];return YES;
}
- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
    if(!url.isFileURL)return NO;
    PGLibraryController *controller=(PGLibraryController *)self.window.rootViewController;
    if(![controller isKindOfClass:PGLibraryController.class])return NO;
    // A CBZ opened from Files is copied into the app's offline library.
    [controller loadViewIfNeeded];
    [controller importDocumentURL:url];
    return YES;
}
@end