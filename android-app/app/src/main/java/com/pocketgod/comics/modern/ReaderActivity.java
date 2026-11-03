package com.pocketgod.comics.modern;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.RectF;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.ColorDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.GestureDetector;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public final class ReaderActivity extends Activity {
    private JSONObject book;
    private JSONArray pages;
    private String id;
    private int page=0;
    private boolean doublePage=false;
    private boolean barsVisible=true;
    private FrameLayout root;
    private LinearLayout top,bottom;
    private TextView counter, title;
    private ImageView bookmark;
    private ImageView singlePageIcon, twoPageIcon;
    private final Handler ui=new Handler(Looper.getMainLooper());
    private final ExecutorService imageWorker=Executors.newSingleThreadExecutor();
    private boolean turning=false;
    private ComicCanvas surface;
    private SeekBar scrubber;
    private boolean changing=false;

    int dp(float n){return (int)(getResources().getDisplayMetrics().density*n+.5f);}
    boolean tablet(){return getResources().getConfiguration().smallestScreenWidthDp>=600;}
    boolean landscape(){return getResources().getConfiguration().orientation==Configuration.ORIENTATION_LANDSCAPE;}
    boolean spread(){return tablet()&&landscape()&&doublePage&&page>0;}
    void fullscreen(){
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN,WindowManager.LayoutParams.FLAG_FULLSCREEN);
        getWindow().setNavigationBarColor(Color.BLACK);
    }
    @Override public void onCreate(Bundle state){
        super.onCreate(state);fullscreen();
        id=getIntent().getStringExtra("id");
        doublePage=ComicStore.prefs(this).getBoolean("two-page",false);
        try{loadIssue(id,true);}catch(Exception ex){error(ex);}
    }
    void loadIssue(String uid,boolean restore) throws Exception {
        book=ComicStore.find(this,uid);id=uid;
        pages=book.getJSONArray("pages");
        page=restore?ComicStore.prefs(this).getInt("progress-"+id,0):0;
        page=Math.max(0,Math.min(page,pages.length()-1));
        buildUI();
        showPage();
    }
    TextView text(String s,int size){
        TextView t=new TextView(this);t.setText(s);t.setTextColor(Color.WHITE);
        t.setTextSize(size);t.setGravity(Gravity.CENTER);
        t.setIncludeFontPadding(false);t.setTypeface(Typeface.DEFAULT,Typeface.BOLD);
        return t;
    }
    GradientDrawable bg(){
        GradientDrawable d=new GradientDrawable();
        // The original UIKit reader uses translucent black chrome, not teal UI panels.
        d.setColor(Color.argb(199,0,0,0));
        return d;
    }
    ImageView originalIcon(String path,String label,int width,int height){
        ImageView icon=new ImageView(this);
        icon.setImageBitmap(ComicStore.bitmap(this,path,256));
        icon.setScaleType(ImageView.ScaleType.FIT_CENTER);
        icon.setPadding(dp(4),dp(3),dp(4),dp(3));
        icon.setContentDescription(label);
        return icon;
    }
    void updateModeIcons(){
        if(singlePageIcon!=null)singlePageIcon.setAlpha(doublePage?.55f:1f);
        if(twoPageIcon!=null)twoPageIcon.setAlpha(doublePage?1f:.55f);
    }
    void buildUI(){
        if(surface!=null)surface.dispose();
        root=new FrameLayout(this);root.setBackgroundColor(Color.BLACK);
        setContentView(root);
        surface=new ComicCanvas();
        root.addView(surface,new FrameLayout.LayoutParams(-1,-1));
        top=new LinearLayout(this);top.setGravity(Gravity.CENTER_VERTICAL);
        top.setPadding(dp(3),dp(2),dp(6),dp(2));top.setBackground(bg());
        FrameLayout.LayoutParams topParams=new FrameLayout.LayoutParams(-1,dp(38),Gravity.TOP);
        root.addView(top,topParams);
        TextView back=text("‹  My Comics",tablet()?14:12);
        top.addView(back,new LinearLayout.LayoutParams(dp(115),-1));
        back.setOnClickListener(v->finish());
        title=text(book.optString("title"),tablet()?14:11);
        title.setSingleLine(true);
        title.setEllipsize(android.text.TextUtils.TruncateAt.END);
        top.addView(title,new LinearLayout.LayoutParams(0,-1,1));
        title.setGravity(Gravity.CENTER_VERTICAL|Gravity.RIGHT);
        bookmark=originalIcon("assets/ipa_original/bookmark@2x.png","Bookmark current page",40,35);
        top.addView(bookmark,new LinearLayout.LayoutParams(dp(40),-1));
        bookmark.setOnClickListener(v->toggleBookmark());
        bookmark.setOnLongClickListener(v->{jumpToBookmark();return true;});
        if(tablet()&&landscape()){
            LinearLayout mode=new LinearLayout(this);
            mode.setGravity(Gravity.CENTER);
            mode.setOrientation(LinearLayout.HORIZONTAL);
            singlePageIcon=originalIcon("assets/ipa_original/single_page_spread_white@2x.png","Single page",78,30);
            twoPageIcon=originalIcon("assets/ipa_original/two_page_spread_white@2x.png","Two pages",78,30);
            mode.addView(singlePageIcon,new LinearLayout.LayoutParams(0,dp(31),1));
            mode.addView(twoPageIcon,new LinearLayout.LayoutParams(0,dp(31),1));
            top.addView(mode,new LinearLayout.LayoutParams(dp(156),-1));
            singlePageIcon.setOnClickListener(v->selectSpread(false));
            twoPageIcon.setOnClickListener(v->selectSpread(true));
            updateModeIcons();
        }else{
            singlePageIcon=null;twoPageIcon=null;
        }
        bottom=new LinearLayout(this);
        bottom.setGravity(Gravity.CENTER_VERTICAL);
        bottom.setBackground(bg());bottom.setPadding(dp(4),0,dp(8),0);
        root.addView(bottom,new FrameLayout.LayoutParams(-1,dp(48),Gravity.BOTTOM));
        counter=text("1 / "+pages.length(),13);
        counter.setTypeface(Typeface.create("monospace",Typeface.BOLD));
        bottom.addView(counter,new LinearLayout.LayoutParams(dp(104),-1));
        scrubber=new SeekBar(this);
        scrubber.setMax(Math.max(0,pages.length()-1));
        scrubber.setContentDescription("Comic page slider");
        scrubber.setProgressTintList(android.content.res.ColorStateList.valueOf(Color.rgb(247,211,115)));
        scrubber.setThumbTintList(android.content.res.ColorStateList.valueOf(Color.rgb(247,211,115)));
        bottom.addView(scrubber,new LinearLayout.LayoutParams(0,-1,1));
        scrubber.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
            @Override public void onStartTrackingTouch(SeekBar v){}
            @Override public void onProgressChanged(SeekBar v,int value,boolean user){
                if(user && !changing){page=value;showPage();}
            }
            @Override public void onStopTrackingTouch(SeekBar v){}
        });
        top.setVisibility(barsVisible?View.VISIBLE:View.GONE);
        bottom.setVisibility(barsVisible?View.VISIBLE:View.GONE);
        // Android 15/16 enforces edge-to-edge for modern target SDKs.
        // Keep page artwork full-bleed but move controls out of cutouts and
        // the navigation gesture / 3-button areas when those are visible.
        if(android.os.Build.VERSION.SDK_INT>=28){
            root.setOnApplyWindowInsetsListener((view,insets)->{
                android.view.DisplayCutout cutout=insets.getDisplayCutout();
                int cutTop=cutout==null?0:cutout.getSafeInsetTop();
                int cutLeft=cutout==null?0:cutout.getSafeInsetLeft();
                int cutRight=cutout==null?0:cutout.getSafeInsetRight();
                int navBottom=android.os.Build.VERSION.SDK_INT>=30
                   ?insets.getInsets(android.view.WindowInsets.Type.navigationBars()).bottom
                   :insets.getSystemWindowInsetBottom();
                FrameLayout.LayoutParams topBar=(FrameLayout.LayoutParams)top.getLayoutParams();
                int targetTop=dp(38)+cutTop;
                if(topBar.height!=targetTop){
                    topBar.height=targetTop;top.setLayoutParams(topBar);
                }
                top.setPadding(dp(3)+cutLeft,dp(2)+cutTop,dp(6)+cutRight,dp(2));
                FrameLayout.LayoutParams bottomBar=(FrameLayout.LayoutParams)bottom.getLayoutParams();
                int targetBottom=dp(48)+navBottom;
                if(bottomBar.height!=targetBottom){
                    bottomBar.height=targetBottom;bottom.setLayoutParams(bottomBar);
                }
                bottom.setPadding(dp(4),0,dp(8),navBottom);
                return insets;
            });
            root.requestApplyInsets();
        }
    }
    void selectSpread(boolean requested){
        if(doublePage==requested)return;
        doublePage=requested;
        ComicStore.prefs(this).edit().putBoolean("two-page",doublePage).apply();
        updateModeIcons();
        if(doublePage && page>0)page=1+((page-1)/2)*2;
        showPage();
    }
    void toggleBars(){
        barsVisible=!barsVisible;
        top.setVisibility(barsVisible?View.VISIBLE:View.GONE);
        bottom.setVisibility(barsVisible?View.VISIBLE:View.GONE);
    }
    void showPage(){
        if(surface==null||pages==null)return;
        page=Math.max(0,Math.min(page,pages.length()-1));
        if(spread())page=1+((page-1)/2)*2;
        String first=pages.optString(page),second=null;
        if(spread()&&page+1<pages.length())second=pages.optString(page+1);
        surface.load(first,second);
        int end=(second!=null)?page+2:page+1;
        counter.setText((page+1)+(end>page+1?"–"+end:"")+" / "+pages.length());
        changing=true;scrubber.setProgress(page);changing=false;
        ComicStore.prefs(this).edit().putInt("progress-"+id,page).putString("last",id).apply();
        int saved=ComicStore.prefs(this).getInt("bookmark-"+id,-1);
        bookmark.setAlpha(saved==page?1f:.55f);
        bookmark.setContentDescription(saved==page?"Remove page bookmark":"Bookmark current page");
    }
    void next(){
        if(turning||surface.scale>1.01f)return;
        int delta=spread()?2:1;
        int target=page+delta;
        if(target>=pages.length()){bookEnd();return;}
        flipTo(target);
    }
    void previous(){
        if(turning||surface.scale>1.01f||page==0)return;
        int delta=spread()&&page>1?2:1;
        flipTo(Math.max(0,page-delta));
    }
    void flipTo(int target){
        if(surface==null || turning)return;
        turning=true;
        // Subtle directional page transition, matching iVerse timing more
        // closely than the old full-screen flash/fade.
        final float direction=target>page?-1f:1f;
        surface.animate().translationX(dp(14)*direction).alpha(.80f)
          .setDuration(135).withEndAction(()->{
             page=target;showPage();
             surface.setTranslationX(dp(14)*(-direction));
             surface.animate().translationX(0).alpha(1f).setDuration(165)
               .withEndAction(()->turning=false).start();
          }).start();
    }
    void toggleBookmark(){
        int saved=ComicStore.prefs(this).getInt("bookmark-"+id,-1);
        ComicStore.prefs(this).edit().putInt("bookmark-"+id,saved==page?-1:page).apply();
        showPage();
    }
    void jumpToBookmark(){
        int saved=ComicStore.prefs(this).getInt("bookmark-"+id,-1);
        if(saved>=0 && saved<pages.length()){page=saved;showPage();}
    }
    void bookEnd(){
        JSONArray current;
        try {
            boolean custom="custom".equals(book.optString("kind"));
            current=ComicStore.books(this,custom);
            JSONObject nextBook=null;
            for(int i=0;i<current.length()-1;i++){
                if(id.equals(current.getJSONObject(i).optString("id"))){
                    nextBook=current.getJSONObject(i+1);break;
                }
            }
            final JSONObject upcoming=nextBook;
            AlertDialog.Builder dialog=new AlertDialog.Builder(this).setTitle("End of Issue")
                .setMessage(upcoming==null?"You've reached the end of this collection.":"Continue reading "+upcoming.optString("title")+"?")
                .setNegativeButton("Stay Here",(d,w)->{})
                .setNeutralButton("My Comics",(d,w)->finish());
            if(upcoming!=null){
                dialog.setPositiveButton("Next Issue",(d,w)->{
                    try{loadIssue(upcoming.optString("id"),false);}
                    catch(Exception ex){error(ex);}
                });
            }
            dialog.show();
        }catch(Exception ex){error(ex);}
    }
    void error(Exception ex){
        new AlertDialog.Builder(this).setTitle("Pocket God Comics")
            .setMessage(ex.getMessage()==null?"Unable to open comic":ex.getMessage())
            .setPositiveButton("Back",(d,w)->finish()).show();
    }
    @Override public void onConfigurationChanged(Configuration configuration){
        super.onConfigurationChanged(configuration);
        buildUI();showPage();
    }
    @Override protected void onDestroy(){
        if(surface!=null)surface.dispose();
        imageWorker.shutdownNow();
        super.onDestroy();
    }

    private final class ComicCanvas extends View {
        private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG);
        private Bitmap first,second;
        private int imageGeneration=0;
        private final ScaleGestureDetector scaleDetector;
        private final GestureDetector gestures;
        float scale=1f,offsetX=0,offsetY=0;
        ComicCanvas(){
            super(ReaderActivity.this);
            // Keep the iOS-style pan/zoom responsive via hardware-accelerated Canvas.
            scaleDetector=new ScaleGestureDetector(ReaderActivity.this,new ScaleGestureDetector.SimpleOnScaleGestureListener(){
                @Override public boolean onScale(ScaleGestureDetector d){
                    scale=Math.min(4f,Math.max(1f,scale*d.getScaleFactor()));
                    if(scale<=1.01f){offsetX=0;offsetY=0;}
                    invalidate();return true;
                }
            });
            gestures=new GestureDetector(ReaderActivity.this,new GestureDetector.SimpleOnGestureListener(){
                @Override public boolean onDown(MotionEvent e){return true;}
                @Override public boolean onDoubleTap(MotionEvent e){
                    scale=scale>1.05f?1f:2.2f;offsetX=0;offsetY=0;invalidate();return true;
                }
                @Override public boolean onSingleTapConfirmed(MotionEvent e){
                    if(scale>1.05f)return false;
                    float relative=e.getX()/Math.max(1,getWidth());
                    if(relative<.23f)previous();
                    else if(relative>.77f)next();
                    else toggleBars();
                    return true;
                }
                @Override public boolean onFling(MotionEvent a,MotionEvent b,float vx,float vy){
                    if(scale>1.05f || Math.abs(vx)<450 || Math.abs(vx)<Math.abs(vy))return false;
                    if(vx<0)next();else previous();
                    return true;
                }
                @Override public boolean onScroll(MotionEvent a,MotionEvent b,float dx,float dy){
                    if(scale<=1.05f)return false;
                    offsetX-=dx;offsetY-=dy;clamp();invalidate();return true;
                }
            });
        }
        void load(String left,String right){
            final int generation=++imageGeneration;
            scale=1;offsetX=0;offsetY=0;
            // Decode full page images off the UI thread to avoid visible
            // freezes while turning pages or dragging the scrubber.
            imageWorker.submit(()->{
                Bitmap incoming=ComicStore.bitmap(ReaderActivity.this,left,right==null?2600:1800);
                Bitmap companion=right!=null?ComicStore.bitmap(ReaderActivity.this,right,1800):null;
                ui.post(()->{
                    if(isFinishing() || isDestroyed() || generation!=imageGeneration){
                        if(incoming!=null)incoming.recycle();
                        if(companion!=null)companion.recycle();
                        return;
                    }
                    Bitmap oldFirst=first,oldSecond=second;
                    first=incoming;second=companion;invalidate();
                    if(oldFirst!=null && oldFirst!=first)oldFirst.recycle();
                    if(oldSecond!=null && oldSecond!=second)oldSecond.recycle();
                });
            });
        }
        void dispose(){
            imageGeneration++;
            if(first!=null){first.recycle();first=null;}
            if(second!=null){second.recycle();second=null;}
        }
        void clamp(){
            float maxX=Math.max(0,(scale-1)*getWidth()*.5f);
            float maxY=Math.max(0,(scale-1)*getHeight()*.5f);
            offsetX=Math.min(maxX,Math.max(-maxX,offsetX));
            offsetY=Math.min(maxY,Math.max(-maxY,offsetY));
        }
        void fitted(Canvas c,Bitmap bmp,RectF slot){
            if(bmp==null)return;
            float ratio=Math.min(slot.width()/bmp.getWidth(),slot.height()/bmp.getHeight());
            float w=bmp.getWidth()*ratio,h=bmp.getHeight()*ratio;
            RectF target=new RectF(slot.centerX()-w/2,slot.centerY()-h/2,slot.centerX()+w/2,slot.centerY()+h/2);
            c.drawBitmap(bmp,null,target,paint);
        }
        @Override protected void onDraw(Canvas c){
            super.onDraw(c);c.drawColor(Color.rgb(10,10,10));
            c.save();c.translate(getWidth()/2f+offsetX,getHeight()/2f+offsetY);
            c.scale(scale,scale);c.translate(-getWidth()/2f,-getHeight()/2f);
            float w=getWidth(),h=getHeight();
            if(second==null){
                fitted(c,first,new RectF(0,0,w,h));
            }else{
                fitted(c,first,new RectF(0,0,w*.5f-2,h));
                fitted(c,second,new RectF(w*.5f+2,0,w,h));
                paint.setColor(Color.rgb(48,48,48));
                c.drawRect(w*.5f-2,0,w*.5f+2,h,paint);
                paint.setColor(Color.WHITE);
            }
            c.restore();
        }
        @Override public boolean onTouchEvent(MotionEvent event){
            scaleDetector.onTouchEvent(event);
            if(!scaleDetector.isInProgress())gestures.onTouchEvent(event);
            return true;
        }
    }
}
