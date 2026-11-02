package com.pocketgod.comics.modern;

import android.content.Context;
import android.content.SharedPreferences;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.util.LruCache;

import org.json.JSONArray;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.Locale;
import java.util.UUID;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

final class ComicStore {
    private ComicStore() {}
    // UIKit-style resource reuse: shelves use only two repeating original images;
    // sharing decoded bitmaps avoids allocating a new large texture for each row.
    private static final LruCache<String,Bitmap> artworkCache =
        new LruCache<String,Bitmap>(48*1024*1024) {
            @Override protected int sizeOf(String key,Bitmap image){return image.getByteCount();}
        };
    private static boolean canCache(String path){
        return path.startsWith("assets/ipa_original/")
            || path.startsWith("assets/native_thumbs/")
            || (path.startsWith("custom/") && path.endsWith("/0000.jpg"));
    }
    static SharedPreferences prefs(Context ctx) {
        return ctx.getSharedPreferences("comics", Context.MODE_PRIVATE);
    }
    static JSONArray originals(Context ctx) throws Exception {
        try (InputStream stream=ctx.getAssets().open("native_catalog.json")) {
            return new JSONArray(new String(readAll(stream,4*1024*1024),"UTF-8"));
        }
    }
    static JSONArray custom(Context ctx) throws Exception {
        File index=new File(ctx.getFilesDir(),"imported/library.json");
        if(!index.isFile())return new JSONArray();
        try(InputStream stream=new FileInputStream(index)){
            return new JSONArray(new String(readAll(stream,2*1024*1024),"UTF-8"));
        }
    }
    static JSONArray all(Context ctx) throws Exception {
        JSONArray combined=originals(ctx);
        JSONArray extra=custom(ctx);
        for(int i=0;i<extra.length();i++)combined.put(extra.getJSONObject(i));
        return combined;
    }
    static JSONArray books(Context ctx,boolean imported) throws Exception {
        return imported?custom(ctx):originals(ctx);
    }
    static JSONObject find(Context ctx,String id) throws Exception {
        JSONArray books=all(ctx);
        for(int i=0;i<books.length();i++){
            JSONObject book=books.getJSONObject(i);
            if(id.equals(book.optString("id")))return book;
        }
        throw new IOException("Comic not found: "+id);
    }
    static String pathFor(Context ctx,String name) throws IOException {
        if(name==null || !name.startsWith("custom/"))throw new IOException("Not a custom page");
        String[] parts=name.split("/");
        if(parts.length!=4 || !parts[1].matches("custom-[a-f0-9-]{36}")
            || !"pages".equals(parts[2]) || !parts[3].matches("[0-9]{4}\\.(jpg|png|jpeg|gif)"))
            throw new IOException("Invalid custom page path");
        File dir=new File(ctx.getFilesDir(),"imported/"+parts[1]+"/pages");
        return new File(dir,parts[3]).getAbsolutePath();
    }
    static InputStream openImage(Context ctx,String path) throws IOException {
        if(path.startsWith("custom/"))return new FileInputStream(pathFor(ctx,path));
        if(path.startsWith("/") || path.contains(".."))throw new IOException("Invalid asset path");
        return ctx.getAssets().open("web/"+path);
    }
    static Bitmap bitmap(Context ctx,String path,int maxDimension) {
        if(path==null || path.isEmpty())return null;
        boolean cache=canCache(path);
        String key=path+"@"+maxDimension;
        if(cache){
            Bitmap existing=artworkCache.get(key);
            if(existing!=null && !existing.isRecycled())return existing;
        }
        try {
            BitmapFactory.Options bounds=new BitmapFactory.Options();
            bounds.inJustDecodeBounds=true;
            try(InputStream stream=openImage(ctx,path)) {
                BitmapFactory.decodeStream(stream,null,bounds);
            }
            if(bounds.outWidth<=0 || bounds.outHeight<=0
                || bounds.outWidth>12000 || bounds.outHeight>12000
                || (long)bounds.outWidth*bounds.outHeight>40_000_000L)return null;
            int sample=1;
            while(Math.max(bounds.outWidth,bounds.outHeight)/sample>maxDimension && sample<16)sample*=2;
            BitmapFactory.Options decode=new BitmapFactory.Options();
            decode.inSampleSize=sample;
            decode.inPreferredConfig=Bitmap.Config.ARGB_8888;
            try(InputStream stream=openImage(ctx,path)) {
                Bitmap result=BitmapFactory.decodeStream(stream,null,decode);
                if(cache && result!=null)artworkCache.put(key,result);
                return result;
            }
        }catch(Exception ex){return null;}
    }
    static byte[] readAll(InputStream input,int max) throws IOException {
        ByteArrayOutputStream output=new ByteArrayOutputStream();
        byte[] block=new byte[16384];
        int n;
        while((n=input.read(block))!=-1){
            if(n==0)continue;
            if(output.size()+n>max)throw new IOException("Comic file is too large");
            output.write(block,0,n);
        }
        return output.toByteArray();
    }
    private static void saveCustomIndex(Context ctx,JSONArray books) throws Exception {
        File dir=new File(ctx.getFilesDir(),"imported");
        if(!dir.exists()&&!dir.mkdirs())throw new IOException("Cannot create library folder");
        File temp=new File(dir,"library.json.tmp");
        File target=new File(dir,"library.json");
        try(FileOutputStream out=new FileOutputStream(temp)){
            out.write(books.toString().getBytes("UTF-8"));
            out.getFD().sync();
        }
        if(!temp.renameTo(target))throw new IOException("Cannot save imported library index");
    }
    private static class Page {
        String originalName;
        String outputName;
        Page(String original,String output){originalName=original;outputName=output;}
    }
    private static boolean supported(String name){
        String suffix=name.toLowerCase(Locale.ROOT);
        return suffix.endsWith(".jpg")||suffix.endsWith(".jpeg")||suffix.endsWith(".png")||suffix.endsWith(".gif");
    }
    private static String extension(String path){
        String lower=path.toLowerCase(Locale.ROOT);
        if(lower.endsWith(".jpeg"))return "jpeg";
        if(lower.endsWith(".jpg"))return "jpg";
        if(lower.endsWith(".gif"))return "gif";
        return "png";
    }
    static JSONObject importCbz(Context ctx,Uri uri) throws Exception {
        File dir=new File(ctx.getFilesDir(),"imported");
        if(!dir.exists()&&!dir.mkdirs())throw new IOException("Cannot create imported library folder");
        String id="custom-"+UUID.randomUUID().toString().toLowerCase(Locale.ROOT);
        File issue=new File(dir,id);
        File pagesDir=new File(issue,"pages");
        if(!pagesDir.mkdirs())throw new IOException("Cannot create comic pages folder");
        File temp=new File(issue,"upload.cbz");
        boolean completed=false;
        try {
            long inputSize=0;
            try(InputStream input=ctx.getContentResolver().openInputStream(uri);
                FileOutputStream out=new FileOutputStream(temp)){
                if(input==null)throw new IOException("Can't open selected file");
                byte[] buf=new byte[32768];
                int n;
                while((n=input.read(buf))!=-1){
                    inputSize+=n;
                    if(inputSize>250L*1024*1024)throw new IOException("CBZ exceeds 250 MB");
                    out.write(buf,0,n);
                }
            }
            if(inputSize==0)throw new IOException("Empty CBZ file");
            List<Page> pageList=new ArrayList<>();
            long total=0;
            try(ZipInputStream zip=new ZipInputStream(new FileInputStream(temp))){
                ZipEntry entry;
                while((entry=zip.getNextEntry())!=null){
                    if(entry.isDirectory()){zip.closeEntry();continue;}
                    String name=entry.getName();
                    if(!supported(name) || name.startsWith("__MACOSX/") || name.contains("../")
                        || name.startsWith(".") || name.contains("\\")){
                        zip.closeEntry();continue;
                    }
                    if(pageList.size()>=500)throw new IOException("Maximum 500 pages per comic");
                    File file=new File(pagesDir,String.format(Locale.ROOT,"%04d.%s",pageList.size()+1,extension(name)));
                    long size=0;
                    try(FileOutputStream out=new FileOutputStream(file)){
                        byte[] block=new byte[16384];
                        int n;
                        while((n=zip.read(block))!=-1){
                            size+=n;
                            total+=n;
                            if(size>32L*1024*1024 || total>550L*1024*1024)
                                throw new IOException("Compressed comic contains oversized images");
                            out.write(block,0,n);
                        }
                    }
                    // Decode headers only; reject oversized or non-image files.
                    BitmapFactory.Options bounds=new BitmapFactory.Options();
                    bounds.inJustDecodeBounds=true;
                    BitmapFactory.decodeFile(file.getAbsolutePath(),bounds);
                    if(bounds.outWidth<1 || bounds.outHeight<1 || bounds.outWidth>12000
                        || bounds.outHeight>12000 || (long)bounds.outWidth*bounds.outHeight>40_000_000L)
                        throw new IOException("Invalid image in comic");
                    pageList.add(new Page(name,file.getName()));
                    zip.closeEntry(); // verifies CRC for supported entries
                }
            }
            if(pageList.isEmpty())throw new IOException("No comic pages found in CBZ");
            // Page naming must follow original natural order rather than ZIP entry order.
            Collections.sort(pageList,new Comparator<Page>(){
                @Override public int compare(Page a,Page b){
                    return naturalCompare(a.originalName,b.originalName);
                }
            });
            JSONArray pages=new JSONArray();
            for(int i=0;i<pageList.size();i++){
                Page page=pageList.get(i);
                File before=new File(pagesDir,page.outputName);
                File after=new File(pagesDir,String.format(Locale.ROOT,"sorted-%04d.%s",i+1,extension(page.outputName)));
                if(!before.renameTo(after))throw new IOException("Could not order comic pages");
                page.outputName=after.getName();
            }
            for(int i=0;i<pageList.size();i++){
                Page page=pageList.get(i);
                File before=new File(pagesDir,page.outputName);
                File after=new File(pagesDir,String.format(Locale.ROOT,"%04d.%s",i+1,extension(page.outputName)));
                if(!before.renameTo(after))throw new IOException("Could not finalize page ordering");
                pages.put("custom/"+id+"/pages/"+after.getName());
            }
            File first=new File(pagesDir,String.format(Locale.ROOT,"0001.%s",extension(pageList.get(0).outputName)));
            Bitmap cover=bitmap(ctx,pages.getString(0),600);
            String thumb=pages.getString(0);
            if(cover!=null){
                File preview=new File(pagesDir,"0000.jpg");
                try(FileOutputStream out=new FileOutputStream(preview)){
                    cover.compress(Bitmap.CompressFormat.JPEG,83,out);
                }
                cover.recycle();
                thumb="custom/"+id+"/pages/0000.jpg";
            }
            String filename=uri.getLastPathSegment();
            if(filename==null || filename.isEmpty())filename="Imported Comic";
            int slash=filename.lastIndexOf('/');
            filename=filename.substring(slash+1);
            filename=filename.replaceFirst("(?i)\\.cbz$","").replaceFirst("(?i)\\.zip$","");
            if(filename.length()>100)filename=filename.substring(0,100);
            JSONObject book=new JSONObject();
            book.put("id",id);
            book.put("kind","custom");
            book.put("title",filename.isEmpty()?"Imported Comic":filename);
            book.put("pages",pages);
            book.put("cover",pages.getString(0));
            book.put("thumbnail",thumb);
            JSONArray old=custom(ctx);
            old.put(book);
            saveCustomIndex(ctx,old);
            completed=true;
            return book;
        } finally {
            if(temp.exists())temp.delete();
            if(!completed)deleteTree(issue);
        }
    }
    private static int naturalCompare(String a,String b){
        // Sort numbered CBZ pages in human reading order (e.g. 2 before 10).
        int i=0,j=0;
        while(i<a.length()&&j<b.length()){
            char x=a.charAt(i),y=b.charAt(j);
            if(Character.isDigit(x)&&Character.isDigit(y)){
                int ai=i,bj=j;
                while(i<a.length()&&Character.isDigit(a.charAt(i)))i++;
                while(j<b.length()&&Character.isDigit(b.charAt(j)))j++;
                String n=a.substring(ai,i),m=b.substring(bj,j);
                try {
                    int diff=Long.compare(Long.parseLong(n),Long.parseLong(m));
                    if(diff!=0)return diff;
                }catch(NumberFormatException ex){
                    int diff=n.compareTo(m);
                    if(diff!=0)return diff;
                }
            }else{
                int diff=Character.compare(Character.toLowerCase(x),Character.toLowerCase(y));
                if(diff!=0)return diff;
                i++;j++;
            }
        }
        return Integer.compare(a.length()-i,b.length()-j);
    }
    static boolean deleteImported(Context ctx,String id) throws Exception {
        if(!id.matches("custom-[a-f0-9-]{36}"))return false;
        JSONArray all=custom(ctx),filtered=new JSONArray();
        boolean found=false;
        for(int i=0;i<all.length();i++){
            JSONObject b=all.getJSONObject(i);
            if(id.equals(b.optString("id")))found=true;
            else filtered.put(b);
        }
        if(!found)return false;
        saveCustomIndex(ctx,filtered);
        deleteTree(new File(ctx.getFilesDir(),"imported/"+id));
        prefs(ctx).edit().remove("progress-"+id).remove("bookmark-"+id).apply();
        return true;
    }
    private static void deleteTree(File dir){
        if(dir.isDirectory()){
            File[] children=dir.listFiles();
            if(children!=null)for(File child:children)deleteTree(child);
        }
        dir.delete();
    }
}
