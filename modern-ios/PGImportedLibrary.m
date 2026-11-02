#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <ImageIO/ImageIO.h>
#include <string.h>
#import <zlib.h>

// Offline, sandboxed CBZ import. ZIP paths are never used as output paths.
// Only image bytes from a validated archive are written, under generated filenames.
// ZIP64 and encrypted archives are intentionally rejected.

static uint16_t PGZip16(const uint8_t *p){return (uint16_t)(p[0]|((uint16_t)p[1]<<8));}
static uint32_t PGZip32(const uint8_t *p){return (uint32_t)p[0]|((uint32_t)p[1]<<8)|((uint32_t)p[2]<<16)|((uint32_t)p[3]<<24);}
static NSError *PGZipError(NSString *message) {
    return [NSError errorWithDomain:@"PocketGodComics.Import" code:1
                           userInfo:@{NSLocalizedDescriptionKey:message?:@"Invalid comic archive"}];
}
static NSString *PGArchiveRoot(void){
    NSArray *dirs=NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES);
    return [[dirs firstObject] stringByAppendingPathComponent:@"PocketGodComics/Imported"];
}
static NSString *PGArchiveIndex(void){
    return [PGArchiveRoot() stringByAppendingPathComponent:@"library.json"];
}
static NSArray *PGReadImportIndex(void){
    NSData *data=[NSData dataWithContentsOfFile:PGArchiveIndex()];
    id value=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
    if(![value isKindOfClass:NSArray.class])return @[];
    NSMutableArray *result=[NSMutableArray new];
    for(id item in value) {
        if(![item isKindOfClass:NSDictionary.class])continue;
        NSString *uid=item[@"id"];
        NSArray *pages=item[@"pages"];
        if(![uid isKindOfClass:NSString.class] || ![uid hasPrefix:@"custom-"] ||
            ![pages isKindOfClass:NSArray.class] || !pages.count || pages.count>1000)continue;
        BOOL valid=YES;
        for(id page in pages){
            if(![page isKindOfClass:NSString.class] || ![page hasPrefix:[NSString stringWithFormat:@"custom/%@/",uid]]){valid=NO;break;}
        }
        if(valid)[result addObject:item];
    }
    return result;
}
NSArray *PGImportedLibrary(void){
    return PGReadImportIndex();
}
NSString *PGImportedImagePath(NSString *name){
    if(![name isKindOfClass:NSString.class] || ![name hasPrefix:@"custom/"])return nil;
    NSArray *parts=[name componentsSeparatedByString:@"/"];
    if(parts.count!=4 || ![parts[1] hasPrefix:@"custom-"])return nil;
    for(NSString *part in parts){
        if(!part.length || [part isEqualToString:@"."] || [part isEqualToString:@".."] ||
           [part containsString:@"\\"] || [part containsString:@":"])return nil;
    }
    if(![parts[2] isEqualToString:@"pages"])return nil;
    return [[PGArchiveRoot() stringByAppendingPathComponent:parts[1]]
             stringByAppendingPathComponent:[NSString stringWithFormat:@"pages/%@",parts[3]]];
}
static BOOL PGSaveImportIndex(NSArray *items,NSError **error){
    NSData *json=[NSJSONSerialization dataWithJSONObject:items options:NSJSONWritingPrettyPrinted error:error];
    if(!json)return NO;
    return [json writeToFile:PGArchiveIndex() options:NSDataWritingAtomic error:error];
}
static BOOL PGDecodeEntry(NSData *archive,NSDictionary *entry,NSData **result){
    const uint8_t *base=archive.bytes;
    NSUInteger size=archive.length;
    NSUInteger local=[entry[@"offset"] unsignedIntegerValue];
    NSUInteger compressed=[entry[@"compressed"] unsignedIntegerValue];
    NSUInteger inflated=[entry[@"inflated"] unsignedIntegerValue];
    NSInteger method=[entry[@"method"] integerValue];
    if(local>size || size-local<30 || PGZip32(base+local)!=0x04034b50)return NO;
    NSUInteger n=PGZip16(base+local+26),e=PGZip16(base+local+28);
    NSUInteger start=local+30+n+e;
    if(start>size || compressed>size-start)return NO;
    if(inflated==0 || inflated>32*1024*1024 || compressed>32*1024*1024)return NO;
    NSData *out=nil;
    if(method==0){
        if(inflated!=compressed)return NO;
        out=[NSData dataWithBytes:base+start length:inflated];
    }else if(method==8){
        NSMutableData *buffer=[NSMutableData dataWithLength:inflated];
        z_stream stream={0};
        if(inflateInit2(&stream,-MAX_WBITS)!=Z_OK)return NO;
        stream.next_in=(Bytef *)(base+start);stream.avail_in=(uInt)compressed;
        stream.next_out=buffer.mutableBytes;stream.avail_out=(uInt)inflated;
        int status=inflate(&stream,Z_FINISH);
        BOOL complete=(status==Z_STREAM_END && stream.total_out==inflated && stream.total_in==compressed);
        inflateEnd(&stream);
        if(!complete)return NO;
        out=buffer;
    }else return NO;
    uLong check=crc32(0L,Z_NULL,0);
    check=crc32(check,out.bytes,(uInt)out.length);
    if((uint32_t)check!=[entry[@"crc"] unsignedIntValue])return NO;
    *result=out;return YES;
}
static BOOL PGIsSupportedImage(NSString *name){
    NSString *ext=name.pathExtension.lowercaseString;
    return [@[@"png",@"jpg",@"jpeg",@"gif"] containsObject:ext] && ![name.lastPathComponent hasPrefix:@"."];
}
static BOOL PGImageMagic(NSData *data,NSString *ext){
    const uint8_t *p=data.bytes;
    if(data.length<12)return NO;
    if([ext isEqualToString:@"png"])return p[0]==0x89 && p[1]=='P' && p[2]=='N' && p[3]=='G';
    if([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"])return p[0]==0xff && p[1]==0xd8 && p[2]==0xff;
    if([ext isEqualToString:@"gif"])return memcmp(p,"GIF8",4)==0;
    return NO;
}
static NSString *PGNormalizedTitle(NSString *filename){
    NSString *stem=[filename stringByDeletingPathExtension];
    NSString *title=[[stem stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] copy];
    if(title.length>100)title=[title substringToIndex:100];
    return title.length?title:@"Imported Comic";
}

NSDictionary *PGImportComicCBZ(NSURL *url,NSError **error){
    if(!url.isFileURL){
        if(error)*error=PGZipError(@"Choose a CBZ comic file stored on your device.");
        return nil;
    }
    NSDictionary *attributes=[[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:NULL];
    unsigned long long bytes=[attributes fileSize];
    if(bytes==0 || bytes>250ULL*1024*1024){
        if(error)*error=PGZipError(@"The CBZ must be between 1 byte and 250 MB.");
        return nil;
    }
    NSData *archive=[NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
    if(!archive)return nil;
    const uint8_t *p=archive.bytes;
    NSUInteger sz=archive.length;
    // The EOCD record occurs in the final 65,557 bytes; ZIP64 and split archives rejected.
    if(sz<22){if(error)*error=PGZipError(@"The CBZ has no ZIP directory.");return nil;}
    NSInteger found=-1;
    NSInteger lower=MAX(0,(NSInteger)sz-65557);
    for(NSInteger k=(NSInteger)sz-22;k>=lower;k--){
        if(PGZip32(p+k)==0x06054b50 && (NSUInteger)k+22+PGZip16(p+k+20)==sz){found=k;break;}
    }
    if(found<0){if(error)*error=PGZipError(@"The CBZ ZIP directory is missing or damaged.");return nil;}
    const uint8_t *end=p+found;
    NSUInteger count=PGZip16(end+10);
    NSUInteger dirSize=PGZip32(end+12),dirOffset=PGZip32(end+16);
    if(PGZip16(end+4)!=0 || PGZip16(end+6)!=0 || count!=PGZip16(end+8) ||
        count==0 || count>2000 || count==65535 || dirSize==0xffffffff ||
        dirOffset==0xffffffff || dirOffset>sz || dirSize>sz-dirOffset ||
        dirOffset+dirSize>(NSUInteger)found){
        if(error)*error=PGZipError(@"Encrypted, split or ZIP64 CBZ archives are not supported.");
        return nil;
    }
    NSMutableArray *entries=[NSMutableArray array];
    NSUInteger cursor=dirOffset;
    unsigned long long inflatedTotal=0;
    for(NSUInteger i=0;i<count;i++){
        if(cursor>sz || sz-cursor<46 || PGZip32(p+cursor)!=0x02014b50){
            if(error)*error=PGZipError(@"A CBZ directory entry is damaged.");return nil;
        }
        const uint8_t *c=p+cursor;
        unsigned flags=PGZip16(c+8),method=PGZip16(c+10);
        NSUInteger zipped=PGZip32(c+20),plain=PGZip32(c+24);
        NSUInteger nameLen=PGZip16(c+28),extra=PGZip16(c+30),comment=PGZip16(c+32);
        NSUInteger local=PGZip32(c+42);
        NSUInteger length=46+nameLen+extra+comment;
        if(length>sz-cursor || (flags&1) || local==0xffffffff ||
            zipped==0xffffffff || plain==0xffffffff){
            if(error)*error=PGZipError(@"Invalid or encrypted CBZ entry.");return nil;
        }
        NSData *rawName=[NSData dataWithBytes:c+46 length:nameLen];
        NSString *name=[[NSString alloc]initWithData:rawName encoding:NSUTF8StringEncoding];
        if(!name)name=[[NSString alloc]initWithData:rawName encoding:NSISOLatin1StringEncoding];
        if(!name){if(error)*error=PGZipError(@"A CBZ filename cannot be decoded.");return nil;}
        if(PGIsSupportedImage(name) && ![name hasPrefix:@"__MACOSX/"] &&
           ![name containsString:@"../"]){
            if(method!=0 && method!=8){if(error)*error=PGZipError(@"Unsupported image compression.");return nil;}
            if(plain<12 || plain>32*1024*1024 || zipped>32*1024*1024){
                if(error)*error=PGZipError(@"A comic image exceeds the safe size limit.");return nil;
            }
            inflatedTotal+=plain;
            if(inflatedTotal>550ULL*1024*1024 || entries.count>=500){
                if(error)*error=PGZipError(@"This comic contains too many or overly large pages.");return nil;
            }
            [entries addObject:@{@"name":name,
                @"compressed":@(zipped),@"inflated":@(plain),
                @"offset":@(local),@"method":@(method),@"crc":@(PGZip32(c+16))}];
        }
        cursor+=length;
    }
    if(entries.count==0){
        if(error)*error=PGZipError(@"No JPEG, PNG or GIF pages were found.");return nil;
    }
    NSDictionary *disk=[[NSFileManager defaultManager] attributesOfFileSystemForPath:NSHomeDirectory() error:NULL];
    unsigned long long available=[disk[NSFileSystemFreeSize] unsignedLongLongValue];
    if(available && inflatedTotal+30ULL*1024*1024>available){
        if(error)*error=PGZipError(@"Not enough device storage to import this comic.");
        return nil;
    }
    [entries sortUsingComparator:^NSComparisonResult(NSDictionary *left,NSDictionary *right){
        return [left[@"name"] localizedStandardCompare:right[@"name"]];
    }];
    NSString *uuid=[[NSUUID UUID].UUIDString lowercaseString];
    NSString *uid=[@"custom-" stringByAppendingString:uuid];
    NSString *destination=[PGArchiveRoot() stringByAppendingPathComponent:uid];
    NSString *pageDir=[destination stringByAppendingPathComponent:@"pages"];
    NSFileManager *fm=[NSFileManager defaultManager];
    if(![fm createDirectoryAtPath:pageDir withIntermediateDirectories:YES attributes:nil error:error])return nil;
    NSMutableArray *pages=[NSMutableArray array];
    BOOL success=YES;
    for(NSUInteger n=0;n<entries.count;n++){
        NSDictionary *entry=entries[n];
        NSString *ext=[entry[@"name"] pathExtension].lowercaseString;
        NSData *data=nil;
        if(!PGDecodeEntry(archive,entry,&data) || !PGImageMagic(data,ext)){
            if(error)*error=PGZipError(@"A comic page is damaged, invalid or failed its checksum.");
            success=NO;break;
        }
        CGImageSourceRef probe=CGImageSourceCreateWithData((__bridge CFDataRef)data,NULL);
        if(!probe){if(error)*error=PGZipError(@"A comic image could not be opened.");success=NO;break;}
        CFDictionaryRef props=CGImageSourceCopyPropertiesAtIndex(probe,0,NULL);
        NSUInteger width=0,height=0;
        if(props){
            NSDictionary *values=(__bridge NSDictionary *)props;
            width=[values[(__bridge NSString *)kCGImagePropertyPixelWidth] unsignedIntegerValue];
            height=[values[(__bridge NSString *)kCGImagePropertyPixelHeight] unsignedIntegerValue];
            CFRelease(props);
        }
        CFRelease(probe);
        if(!width || !height || width>12000 || height>12000 || (unsigned long long)width*height>40000000ULL){
            if(error)*error=PGZipError(@"A comic image has invalid or unsafe dimensions.");
            success=NO;break;
        }
        NSString *name=[NSString stringWithFormat:@"%04lu.%@",(unsigned long)(n+1),ext];
        NSString *file=[pageDir stringByAppendingPathComponent:name];
        if(![data writeToFile:file options:NSDataWritingAtomic error:error]){success=NO;break;}
        [pages addObject:[NSString stringWithFormat:@"custom/%@/pages/%@",uid,name]];
    }
    if(!success){[fm removeItemAtPath:destination error:NULL];return nil;}
    // Generate a bounded-memory thumbnail for older iPhone and iPad hardware.
    NSString *thumbFile=[pageDir stringByAppendingPathComponent:@"cover-thumb.jpg"];
    NSData *coverData=[NSData dataWithContentsOfFile:[pageDir stringByAppendingPathComponent:[pages[0] lastPathComponent]]];
    CGImageSourceRef source=coverData?CGImageSourceCreateWithData((__bridge CFDataRef)coverData,NULL):NULL;
    CGImageRef small=NULL;
    if(source){
        NSDictionary *opt=@{(__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways:@YES,
                            (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize:@360,
                            (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform:@YES};
        small=CGImageSourceCreateThumbnailAtIndex(source,0,(__bridge CFDictionaryRef)opt);
        CFRelease(source);
    }
    if(small){
        UIImage *image=[UIImage imageWithCGImage:small];
        NSData *jpeg=UIImageJPEGRepresentation(image,.83);
        if(jpeg)[jpeg writeToFile:thumbFile atomically:YES];
        CGImageRelease(small);
    }
    NSString *thumb=[[NSFileManager defaultManager] fileExistsAtPath:thumbFile]?
        [NSString stringWithFormat:@"custom/%@/pages/cover-thumb.jpg",uid]:pages[0];
    NSString *title=PGNormalizedTitle(url.lastPathComponent);
    NSDictionary *book=@{@"id":uid,@"kind":@"custom",@"title":title,
                          @"cover":pages[0],@"thumbnail":thumb,
                          @"pages":pages};
    NSError *indexError=nil;
    NSMutableArray *library=[PGReadImportIndex() mutableCopy];
    [library addObject:book];
    if(!PGSaveImportIndex(library,&indexError)){
        [fm removeItemAtPath:destination error:NULL];
        if(error)*error=indexError;
        return nil;
    }
    return book;
}
BOOL PGRemoveImportedComic(NSString *uid,NSError **error){
    if(![uid isKindOfClass:NSString.class] || ![uid hasPrefix:@"custom-"] ||
       [uid containsString:@"/"] || [uid containsString:@"\\"] || [uid containsString:@".."])return NO;
    NSMutableArray *library=[PGReadImportIndex() mutableCopy];
    NSIndexSet *matches=[library indexesOfObjectsPassingTest:^BOOL(id item,NSUInteger i,BOOL *stop){
        return [item[@"id"] isEqualToString:uid];
    }];
    if(!matches.count)return NO;
    [library removeObjectsAtIndexes:matches];
    if(!PGSaveImportIndex(library,error))return NO;
    [[NSFileManager defaultManager] removeItemAtPath:[PGArchiveRoot() stringByAppendingPathComponent:uid] error:NULL];
    NSUserDefaults *settings=[NSUserDefaults standardUserDefaults];
    [settings removeObjectForKey:[@"native-progress-" stringByAppendingString:uid]];
    [settings removeObjectForKey:[@"native-bookmark-" stringByAppendingString:uid]];
    if([[settings stringForKey:@"native-last-issue"] isEqualToString:uid])
        [settings removeObjectForKey:@"native-last-issue"];
    return YES;
}