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
import android.os.Bundle;
import android.view.GestureDetector;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.View;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

public final class ReaderActivity extends Activity {
    private JSONObject book;
    private JSONArray pages;
    private String id;
    private int page=0;
    private boolean doublePage=false;
    private boolean barsVisible=true;
    private FrameLayout root;
    private LinearLayout top,bottom;
    private TextView counter, title,bookmark;
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
        d.setColor(Color.argb(241,11,51,63));d.setStroke(dp(1),Color.rgb(109,165,165));
        d.setCornerRadius(dp(4));return d;
    }
    void buildUI(){
        if(surface!=null)surface.dispose();
        root=new FrameLayout(this);root.setBackgroundColor(Color.BLACK);
        setContentView(root);
        surface=new ComicCanvas();
        root.addView(surface,new FrameLayout.LayoutParams(-1,-1));
        top=new LinearLayout(this);top.setGravity(Gravity.CENTER_VERTICAL);
        top.setPadding(dp(3),dp(2),dp(6),dp(2));top.setBackground(bg());
        FrameLayout.LayoutParams topParams=new FrameLayout.LayoutParams(-1,dp(44),Gravity.TOP);
        root.addView(top,topParams);
        TextView back=text("‹ My Comics",tablet()?14:12);
        top.addView(back,new LinearLayout.LayoutParams(dp(tablet()?116:96),-1));
        back.setOnClickListener(v->finish());
        title=text(book.optString("title"),tablet()?14:11);
        title.setSingleLine(true);
        title.setEllipsize(android.text.TextUtils.TruncateAt.END);
        top.addView(title,new LinearLayout.LayoutParams(0,-1,1));
        bookmark=text("☆",24);
        bookmark.setContentDescription("Bookmark current page");
        top.addView(bookmark,new LinearLayout.LayoutParams(dp(42),-1));
        bookmark.setOnClickListener(v->toggleBookmark());
        bookmark.setOnLongClickListener(v->{jumpToBookmark();return true;});
        if(tablet()&&landscape()){
            TextView mode=text(doublePage?"2 Pages":"1 Page",12);
            mode.setBackground(bg());
            top.addView(mode,new LinearLayout.LayoutParams(dp(78),dp(36)));
            mode.setOnClickListener(v->{
                doublePage=!doublePage;
                ComicStore.prefs(this).edit().putBoolean("two-page",doublePage).apply();
                mode.setText(doublePage?"2 Pages":"1 Page");
                if(doublePage && page>0)page=1+((page-1)/2)*2;
                showPage();
            });
        }
        bottom=new LinearLayout(this);
        bottom.setGravity(Gravity.CENTER_VERTICAL);
        bottom.setBackground(bg());bottom.setPadding(dp(4),0,dp(8),0);
        root.addView(bottom,new FrameLayout.LayoutParams(-1,dp(52),Gravity.BOTTOM));
        TextView previous=text("‹",30);
        bottom.addView(previous,new LinearLayout.LayoutParams(dp(36),-1));
        previous.setOnClickListener(v->previous());
        counter=text("1 / "+pages.length(),12);
        bottom.addView(counter,new LinearLayout.LayoutParams(dp(tablet()?116:83),-1));
        scrubber=new SeekBar(this);
        scrubber.setMax(Math.max(0,pages.length()-1));
        scrubber.setContentDescription("Comic page slider");
        bottom.addView(scrubber,new LinearLayout.LayoutParams(0,-1,1));
        scrubber.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener(){
            @Override public void onStartTrackingTouch(SeekBar v){}
            @Override public void onProgressChanged(SeekBar v,int value,boolean user){
                if(user && !changing){page=value;showPage();}
            }
            @Override public void onStopTrackingTouch(SeekBar v){}
        });
        TextView next=text("›",30);
        bottom.addView(next,new LinearLayout.LayoutParams(dp(36),-1));
        next.setOnClickListener(v->next());
        top.setVisibility(barsVisible?View.VISIBLE:View.GONE);
        bottom.setVisibility(barsVisible?View.VISIBLE:View.GONE);
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
        bookmark.setText(saved==page?"★":"☆");
    }
    void next(){
        if(surface.scale>1.01f)return;
        int delta=spread()?2:1;
        int target=page+delta;
        if(target>=pages.length()){bookEnd();return;}
        flipTo(target);
    }
    void previous(){
        if(surface.scale>1.01f||page==0)return;
        int delta=spread()&&page>1?2:1;
        flipTo(Math.max(0,page-delta));
    }
    void flipTo(int target){
        if(surface==null)return;
        surface.animate().alpha(.32f).setDuration(100).withEndAction(()->{
            page=target;showPage();
            surface.animate().alpha(1f).setDuration(120).start();
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
        super.onDestroy();
    }

    private final class ComicCanvas extends View {
        private final Paint paint=new Paint(Paint.ANTI_ALIAS_FLAG|Paint.FILTER_BITMAP_FLAG);
        private Bitmap first,second;
        private final ScaleGestureDetector scaleDetector;
        private final GestureDetector gestures;
        float scale=1f,offsetX=0,offsetY=0;
        ComicCanvas(){
            super(ReaderActivity.this);setLayerType(View.LAYER_TYPE_SOFTWARE,null);
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
            dispose();
            first=ComicStore.bitmap(ReaderActivity.this,left,right==null?2600:1800);
            if(right!=null)second=ComicStore.bitmap(ReaderActivity.this,right,1800);
            scale=1;offsetX=0;offsetY=0;
            invalidate();
        }
        void dispose(){
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
