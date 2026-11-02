package com.pocketgod.comics.modern;

import android.app.Activity;
import android.app.AlertDialog;
import android.app.ProgressDialog;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.res.Configuration;
import android.graphics.Bitmap;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.GradientDrawable;
import android.net.Uri;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.WindowManager;
import android.widget.EditText;
import android.widget.FrameLayout;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.text.Editable;
import android.text.TextWatcher;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.IOException;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

public final class MainActivity extends Activity {
    private static final int REQUEST_CBZ=31;
    private boolean custom=false;
    private boolean list=false;
    private String search="";
    private LinearLayout root, shelf;
    private ScrollView scroll;
    private TextView heading, empty;
    private final Handler handler=new Handler(Looper.getMainLooper());

    int dp(float n){return (int)(n*getResources().getDisplayMetrics().density+.5f);}
    boolean tablet(){return getResources().getConfiguration().smallestScreenWidthDp>=600;}
    boolean landscape(){return getResources().getConfiguration().orientation==Configuration.ORIENTATION_LANDSCAPE;}
    void fullscreen(){
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN,WindowManager.LayoutParams.FLAG_FULLSCREEN);
        getWindow().setNavigationBarColor(Color.rgb(5,24,31));
    }
    @Override public void onCreate(Bundle b){
        super.onCreate(b);fullscreen();
        list=ComicStore.prefs(this).getBoolean("list-mode",false);
        buildShell();
        if(getIntent()!=null && Intent.ACTION_VIEW.equals(getIntent().getAction())){
            Uri uri=getIntent().getData();if(uri!=null)importUri(uri);
        }
    }
    @Override protected void onNewIntent(Intent i){
        super.onNewIntent(i);setIntent(i);
        if(Intent.ACTION_VIEW.equals(i.getAction())&&i.getData()!=null)importUri(i.getData());
    }
    @Override public void onConfigurationChanged(Configuration c){
        super.onConfigurationChanged(c);buildShell();
    }
    @Override protected void onResume(){
        super.onResume();if(shelf!=null)populate();
    }
    TextView label(String txt,int sp,int color,boolean bold){
        TextView v=new TextView(this);
        v.setText(txt);v.setTextColor(color);v.setTextSize(sp);
        v.setGravity(Gravity.CENTER);v.setIncludeFontPadding(false);
        if(bold)v.setTypeface(Typeface.DEFAULT,Typeface.BOLD);
        return v;
    }
    void backgroundFromAsset(View v,String asset){
        Bitmap bitmap=ComicStore.bitmap(this,asset,1350);
        if(bitmap!=null){
            BitmapDrawable d=new BitmapDrawable(getResources(),bitmap);
            d.setGravity(Gravity.FILL);
            v.setBackground(d);
        }
    }
    GradientDrawable panel(int color,int radius){
        GradientDrawable d=new GradientDrawable();d.setColor(color);d.setCornerRadius(dp(radius));
        d.setStroke(dp(1),Color.argb(125,230,194,107));return d;
    }
    void buildShell(){
        LinearLayout outer=new LinearLayout(this);
        outer.setOrientation(LinearLayout.VERTICAL);
        outer.setBackgroundColor(Color.rgb(24,102,122));
        root=outer;
        setContentView(outer);

        FrameLayout masthead=new FrameLayout(this);
        masthead.setBackgroundColor(Color.rgb(46,150,166));
        backgroundFromAsset(masthead,"assets/ipa_original/shelfBlueiPad@2x.png");
        outer.addView(masthead,new LinearLayout.LayoutParams(-1,dp(tablet()?110:85)));
        ImageView logo=new ImageView(this);
        logo.setScaleType(ImageView.ScaleType.FIT_CENTER);
        logo.setImageBitmap(ComicStore.bitmap(this,"assets/ipa_original/native_header_logo.png",720));
        FrameLayout.LayoutParams lp=new FrameLayout.LayoutParams(dp(tablet()?325:265),-1,Gravity.CENTER);
        masthead.addView(logo,lp);

        heading=label(custom?"Custom Comics":"My Comics",tablet()?22:19,Color.WHITE,true);
        heading.setShadowLayer(dp(2),0,dp(2),Color.BLACK);
        backgroundFromAsset(heading,"assets/ipa_original/drawer_bg@2x.png");
        outer.addView(heading,new LinearLayout.LayoutParams(-1,dp(tablet()?44:39)));

        LinearLayout toolbar=new LinearLayout(this);
        toolbar.setOrientation(LinearLayout.HORIZONTAL);
        toolbar.setGravity(Gravity.CENTER_VERTICAL);
        toolbar.setPadding(dp(6),dp(3),dp(6),dp(3));
        toolbar.setBackgroundColor(Color.rgb(11,58,72));
        outer.addView(toolbar,new LinearLayout.LayoutParams(-1,dp(48)));
        TextView toggle=label(list?"List":"Shelf",13,Color.WHITE,true);
        toggle.setBackground(panel(Color.rgb(29,105,132),5));
        toolbar.addView(toggle,new LinearLayout.LayoutParams(dp(66),dp(37)));
        toggle.setOnClickListener(v->{list=!list;ComicStore.prefs(this).edit().putBoolean("list-mode",list).apply();toggle.setText(list?"List":"Shelf");populate();});

        EditText filter=new EditText(this);
        filter.setSingleLine(true);filter.setTextSize(14);filter.setTextColor(Color.WHITE);
        filter.setHintTextColor(Color.LTGRAY);filter.setHint("Search comics");
        filter.setBackground(panel(Color.rgb(21,77,89),5));
        filter.setPadding(dp(10),0,dp(7),0);
        filter.setText(search);
        LinearLayout.LayoutParams filterParams=new LinearLayout.LayoutParams(0,dp(38),1);
        filterParams.setMargins(dp(5),0,dp(5),0);
        toolbar.addView(filter,filterParams);
        filter.addTextChangedListener(new TextWatcher(){
            @Override public void beforeTextChanged(CharSequence s,int a,int count,int after){}
            @Override public void onTextChanged(CharSequence s,int start,int before,int count){
                search=s.toString();populate();
            }
            @Override public void afterTextChanged(Editable e){}
        });
        TextView add=label("＋",26,Color.WHITE,true);
        add.setContentDescription("Import CBZ from Files");
        add.setBackground(panel(Color.rgb(29,105,132),5));
        toolbar.addView(add,new LinearLayout.LayoutParams(dp(39),dp(37)));
        add.setOnClickListener(v->openPicker());

        TextView settings=label("⚙",23,Color.WHITE,false);
        settings.setContentDescription("Reader settings");
        toolbar.addView(settings,new LinearLayout.LayoutParams(dp(40),dp(37)));
        settings.setOnClickListener(v->showSettings());

        scroll=new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setVerticalScrollBarEnabled(true);
        scroll.setBackgroundColor(Color.rgb(46,142,161));
        outer.addView(scroll,new LinearLayout.LayoutParams(-1,0,1));
        FrameLayout shelfContainer=new FrameLayout(this);
        scroll.addView(shelfContainer,new ScrollView.LayoutParams(-1,-2));
        shelf=new LinearLayout(this);
        shelf.setOrientation(LinearLayout.VERTICAL);
        shelfContainer.addView(shelf,new FrameLayout.LayoutParams(-1,-2));
        empty=label("No custom comics yet\nImport a CBZ from Files to get started",17,Color.WHITE,true);
        empty.setPadding(dp(25),dp(36),dp(25),dp(36));
        empty.setVisibility(View.GONE);
        shelfContainer.addView(empty,new FrameLayout.LayoutParams(-1,dp(190),Gravity.TOP));
        empty.setOnClickListener(v->openPicker());

        LinearLayout bottom=new LinearLayout(this);
        bottom.setGravity(Gravity.CENTER);
        bottom.setPadding(dp(7),dp(5),dp(7),dp(5));
        backgroundFromAsset(bottom,"assets/ipa_original/drawer_bg@2x.png");
        outer.addView(bottom,new LinearLayout.LayoutParams(-1,dp(tablet()?63:58)));
        TextView original=tab("My Comics",!custom);
        TextView imported=tab("Custom",custom);
        LinearLayout.LayoutParams weight=new LinearLayout.LayoutParams(0,-1,1);
        weight.setMargins(dp(3),0,dp(3),0);
        bottom.addView(original,weight);
        bottom.addView(imported,new LinearLayout.LayoutParams(0,-1,1));
        imported.setOnClickListener(v->{custom=true;search="";buildShell();});
        original.setOnClickListener(v->{custom=false;search="";buildShell();});
        populate();
    }
    TextView tab(String name,boolean selected){
        TextView b=label(name,15,Color.WHITE,true);
        if(selected)backgroundFromAsset(b,"assets/ipa_original/blue_button.png");
        else b.setBackground(panel(Color.argb(130,15,54,67),5));
        return b;
    }
    void populate(){
        if(shelf==null)return;
        shelf.removeAllViews();
        try{
            JSONArray data=ComicStore.books(this,custom);
            List<JSONObject> books=new ArrayList<>();
            for(int i=0;i<data.length();i++){
                JSONObject book=data.getJSONObject(i);
                if(book.optString("title").toLowerCase(Locale.ROOT).contains(search.toLowerCase(Locale.ROOT)))
                    books.add(book);
            }
            empty.setVisibility(custom&&data.length()==0?View.VISIBLE:View.GONE);
            if(list){
                for(JSONObject item:books)shelf.addView(listRow(item));
            }else{
                int cols=tablet()?(landscape()?4:2):2;
                int rowHeight=tablet()?(landscape()?300:340):205;
                String layout=tablet()?(landscape()?"ipad_landscape":"ipad_portrait"):"phone";
                for(int start=0,row=0;start<books.size();start+=cols,row++){
                    FrameLayout section=new FrameLayout(this);
                    section.setBackgroundColor(Color.rgb(45,143,156));
                    backgroundFromAsset(section,"assets/ipa_original/native_shelf_"+layout+"_"+(row%2)+".png");
                    shelf.addView(section,new LinearLayout.LayoutParams(-1,dp(rowHeight)));
                    LinearLayout cells=new LinearLayout(this);
                    cells.setOrientation(LinearLayout.HORIZONTAL);
                    section.addView(cells,new FrameLayout.LayoutParams(-1,-1));
                    for(int col=0;col<cols;col++){
                        JSONObject issue=start+col<books.size()?books.get(start+col):null;
                        View cell=issue==null?new View(this):bookCover(issue,rowHeight);
                        cells.addView(cell,new LinearLayout.LayoutParams(0,-1,1));
                    }
                }
            }
        }catch(Exception e){
            shelf.addView(label("Cannot load comics: "+e.getMessage(),15,Color.WHITE,false));
        }
    }
    View bookCover(JSONObject issue,int rowHeight){
        LinearLayout container=new LinearLayout(this);
        container.setOrientation(LinearLayout.VERTICAL);
        container.setGravity(Gravity.TOP|Gravity.CENTER_HORIZONTAL);
        container.setPadding(dp(5),dp(8),dp(5),0);
        ImageView cover=new ImageView(this);
        cover.setScaleType(ImageView.ScaleType.FIT_CENTER);
        cover.setImageBitmap(ComicStore.bitmap(this,issue.optString("thumbnail",issue.optString("cover")),600));
        GradientDrawable edge=panel(Color.argb(180,5,54,78),4);
        cover.setBackground(edge);
        cover.setPadding(dp(3),dp(3),dp(3),dp(3));
        container.addView(cover,new LinearLayout.LayoutParams(-1,dp(rowHeight-56)));
        TextView title=label(issue.optString("title"),tablet()?12:10,Color.WHITE,true);
        title.setShadowLayer(dp(2),0,dp(2),Color.BLACK);
        title.setMaxLines(2);
        title.setEllipsize(android.text.TextUtils.TruncateAt.END);
        container.addView(title,new LinearLayout.LayoutParams(-1,dp(43)));
        container.setOnClickListener(v->openIssue(issue.optString("id")));
        if(custom)container.setOnLongClickListener(v->{confirmDelete(issue);return true;});
        return container;
    }
    View listRow(JSONObject issue){
        LinearLayout container=new LinearLayout(this);
        container.setGravity(Gravity.CENTER_VERTICAL);
        container.setPadding(dp(10),dp(3),dp(10),dp(3));
        container.setBackgroundColor(Color.rgb(17,71,89));
        ImageView cover=new ImageView(this);
        cover.setScaleType(ImageView.ScaleType.FIT_CENTER);
        cover.setImageBitmap(ComicStore.bitmap(this,issue.optString("thumbnail"),320));
        container.addView(cover,new LinearLayout.LayoutParams(dp(57),dp(74)));
        TextView title=label(issue.optString("title"),15,Color.WHITE,true);
        title.setGravity(Gravity.CENTER_VERTICAL|Gravity.START);
        title.setPadding(dp(12),0,dp(4),0);
        container.addView(title,new LinearLayout.LayoutParams(0,dp(75),1));
        container.setOnClickListener(v->openIssue(issue.optString("id")));
        if(custom)container.setOnLongClickListener(v->{confirmDelete(issue);return true;});
        View divider=new View(this);
        divider.setBackgroundColor(Color.rgb(144,183,175));
        LinearLayout wrap=new LinearLayout(this);
        wrap.setOrientation(LinearLayout.VERTICAL);
        wrap.addView(container,new LinearLayout.LayoutParams(-1,dp(80)));
        wrap.addView(divider,new LinearLayout.LayoutParams(-1,dp(1)));
        return wrap;
    }
    void openIssue(String id){
        Intent intent=new Intent(this,ReaderActivity.class);
        intent.putExtra("id",id);
        startActivity(intent);
    }
    void confirmDelete(JSONObject book){
        new AlertDialog.Builder(this).setTitle("Remove Imported Comic?")
          .setMessage(book.optString("title")+"\n\nThe comic and its saved progress will be removed.")
          .setNegativeButton("Cancel",null)
          .setPositiveButton("Remove",(d,w)->{
              try{ComicStore.deleteImported(this,book.optString("id"));populate();}
              catch(Exception e){error(e);}
          }).show();
    }
    void showSettings(){
        String last=ComicStore.prefs(this).getString("last",""), continueText=last.isEmpty()?"About":"Continue Reading";
        String[] options={continueText,"Import CBZ","Shelf / List","About"};
        new AlertDialog.Builder(this).setTitle("Pocket God Comics")
          .setItems(options,(dialog,which)->{
              if(which==0){
                  if(!last.isEmpty())openIssue(last);
                  else about();
              }else if(which==1)openPicker();
              else if(which==2){
                  list=!list;ComicStore.prefs(this).edit().putBoolean("list-mode",list).apply();buildShell();
              }else about();
          }).show();
    }
    void about(){
        new AlertDialog.Builder(this).setTitle("Pocket God Comics — Android 0.1")
          .setMessage("Offline preservation reader\n25 original print issues\nAll comics stored locally\n\nCustom CBZ files can be imported through Files. No login or network required.")
          .setPositiveButton("OK",null).show();
    }
    void openPicker(){
        Intent intent=new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        intent.putExtra(Intent.EXTRA_MIME_TYPES,new String[]{"application/vnd.comicbook+zip","application/zip","application/octet-stream"});
        startActivityForResult(intent,REQUEST_CBZ);
    }
    @Override protected void onActivityResult(int request,int result,Intent data){
        super.onActivityResult(request,result,data);
        if(request==REQUEST_CBZ && result==RESULT_OK && data!=null && data.getData()!=null)
            importUri(data.getData());
    }
    void importUri(Uri uri){
        final ProgressDialog dialog=ProgressDialog.show(this,"Importing comic","Checking and storing pages offline…",true,false);
        new Thread(()->{
            Exception failure=null;
            try{ComicStore.importCbz(this,uri);}
            catch(Exception ex){failure=ex;}
            final Exception result=failure;
            handler.post(()->{
                dialog.dismiss();
                if(result!=null)error(result);
                else {custom=true;search="";buildShell();}
            });
        },"CBZ import").start();
    }
    void error(Exception e){
        new AlertDialog.Builder(this).setTitle("Pocket God Comics")
          .setMessage(e.getMessage()==null?"An operation failed.":e.getMessage())
          .setPositiveButton("OK",null).show();
    }
}
