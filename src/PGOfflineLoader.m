// Project-authored v13 compatibility bridge; original commercial binary is not included.
// Original iVerse interface remains proprietary. Hardware QA still required.
// Pocket God Comics owner archive restoration loader.
// Runs INSIDE the original iVerse binary; does not replace nibs, animations or UI.
// iOS 7 ARMv7, private on-device test; all external comics are packaged locally.
#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreData/CoreData.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dispatch/dispatch.h>

static NSDictionary *pgEntriesByID=nil;
static BOOL pgSeedComplete=NO;
static const void *PGEntryKey = &PGEntryKey;
static IMP pgOrigIpadLaunch=NULL,pgOrigPhoneLaunch=NULL;
static IMP pgOrigIpadLoad=NULL,pgOrigPhoneAppear=NULL,pgOrigPhoneLoadShelf=NULL;
static BOOL pgSeedAttemptRunning=NO, pgRetryScheduled=NO;
static __weak id pgVisibleIpadShelf=nil;
static NSArray *pgCoverMigrationProducts=nil;
static NSUInteger pgCoverMigrationIndex=0;
static BOOL pgCoverMigrationRunning=NO;
static void pgScheduleCoverMigration(void);

static NSUInteger pgLastCatalogEntries=0;
static void pgDiagnostic(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message=[[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"[PGOffline] %@", message);
    @try {
        NSString *documents=[NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,NSUserDomainMask,YES) firstObject];
        if (!documents) return;
        NSString *path=[documents stringByAppendingPathComponent:@"PGOfflineDiagnostics.txt"];
        NSString *line=[NSString stringWithFormat:@"%@ | %@\n",[NSDate date],message];
        NSData *bytes=[line dataUsingEncoding:NSUTF8StringEncoding];
        @synchronized([NSFileManager defaultManager]) {
            if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
                [@"Pocket God Comics original iVerse content-loader diagnostics\n" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            }
            NSFileHandle *handle=[NSFileHandle fileHandleForWritingAtPath:path];
            [handle seekToEndOfFile];
            [handle writeData:bytes];
            [handle closeFile];
        }
    } @catch (NSException *ignored) {}
}

static IMP pgOrigBundleFilePath=NULL,pgOrigRemoveProduct=NULL;
static IMP pgOrigBundleInit=NULL,pgOrigBundleVertical=NULL,pgOrigBundleHorizontal=NULL,
           pgOrigBundleImage=NULL,pgOrigBundleVerticalImage=NULL,pgOrigBundleForcedImage=NULL,
           pgOrigBundleCover=NULL,pgOrigBundleAuthentic=NULL,pgOrigBundleChecksum=NULL,
           pgOrigBundleVertIndex=NULL,pgOrigBundleHorizIndex=NULL,pgOrigProductInstalled=NULL;

static id pgMsg0(id obj, SEL selector) {
    return ((id (*)(id,SEL))objc_msgSend)(obj,selector);
}
static id pgMsg1(id obj, SEL selector,id value) {
    return ((id (*)(id,SEL,id))objc_msgSend)(obj,selector,value);
}
static NSDictionary *pgEntryForProduct(id product) {
    if (!product) return nil;
    NSString *productID=nil;
    @try {productID=[product valueForKey:@"productID"];} @catch(NSException *e) {return nil;}
    if (![productID isKindOfClass:[NSString class]]) return nil;
    return [pgEntriesByID objectForKey:productID];
}
static NSDictionary *pgEntryForBundle(id obj) {
    return (NSDictionary *)objc_getAssociatedObject(obj, PGEntryKey);
}
static NSString *pgIssueDirectory(NSDictionary *entry) {
    NSNumber *number=[entry objectForKey:@"episode"];
    NSString *root=[[NSBundle mainBundle] pathForResource:@"PGOffline" ofType:nil];
    if(!root) root=[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"PGOffline"];
    return [root stringByAppendingPathComponent:[NSString stringWithFormat:@"%03d",[number intValue]]];
}
static UIImage *pgPage(NSDictionary *entry,int pageIndex) {
    NSArray *pages=[entry objectForKey:@"pages"];
    if (![pages isKindOfClass:[NSArray class]] || pageIndex<0 || pageIndex>=(int)[pages count]) return nil;
    NSString *name=[pages objectAtIndex:(NSUInteger)pageIndex];
    if ([name rangeOfString:@"/"].location!=NSNotFound ||
        [name rangeOfString:@".."].location!=NSNotFound) return nil;
    NSString *path=[pgIssueDirectory(entry) stringByAppendingPathComponent:name];
    return [UIImage imageWithContentsOfFile:path];
}
static UIImage *pgCover(NSDictionary *entry) {
    NSString *file=[entry objectForKey:@"cover"];
    if(![file isKindOfClass:[NSString class]] || ![file length])file=@"cover.png";
    if([file rangeOfString:@"/"].location!=NSNotFound ||
       [file rangeOfString:@".."].location!=NSNotFound)return nil;
    NSString *path=[pgIssueDirectory(entry) stringByAppendingPathComponent:file];
    return [UIImage imageWithContentsOfFile:path];
}
static UIImage *pgShelfCover(NSDictionary *entry) {
    // CoreData shelf widgets must NEVER store the full-resolution fan cover.
    NSString *smallPath=[pgIssueDirectory(entry) stringByAppendingPathComponent:@"shelf-cover.jpg"];
    UIImage *small=[UIImage imageWithContentsOfFile:smallPath];
    if(small)return small;
    return pgCover(entry); // legacy fallback only for older installed packages
}
static void pgLoadManifest(void) {
    if (pgEntriesByID) return;
    NSString *path=[[[NSBundle mainBundle] bundlePath] stringByAppendingPathComponent:@"PGOffline/manifest.json"];
    NSData *data=[NSData dataWithContentsOfFile:path];
    NSDictionary *manifest=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
    NSMutableDictionary *byID=[NSMutableDictionary dictionary];
    NSArray *items=[manifest objectForKey:@"episodes"];
    if ([items isKindOfClass:[NSArray class]]) {
        for (NSDictionary *entry in items) {
            NSNumber *episode=[entry objectForKey:@"episode"];
            NSArray *pages=[entry objectForKey:@"pages"];
            if (![episode isKindOfClass:[NSNumber class]] || ![pages isKindOfClass:[NSArray class]] || ![pages count])continue;
            NSString *identifier=[NSString stringWithFormat:@"pg.offline.%03d",[episode intValue]];
            [byID setObject:entry forKey:identifier];
        }
    }
    pgEntriesByID=[byID copy];
    pgLastCatalogEntries=[pgEntriesByID count];
    pgDiagnostic(@"Manifest loaded: %lu episodes; bundlePath=%@; manifestBytes=%lu",
                 (unsigned long)[pgEntriesByID count],[[NSBundle mainBundle] bundlePath],
                 (unsigned long)[data length]);
}
static BOOL pgAttachImage(NSManagedObjectContext *context, NSManagedObject *product,NSString *entityName,NSString *relationship,UIImage *picture) {
    if(!picture)return NO;
    NSManagedObject *image=nil;
    @try {
        image=[NSEntityDescription insertNewObjectForEntityForName:entityName inManagedObjectContext:context];
        [image setValue:picture forKey:@"image"];
        if ([entityName isEqualToString:@"ProductThumbnail"]) [image setValue:picture forKey:@"smallImage"];
        [product setValue:image forKey:relationship];
        return YES;
    } @catch(NSException *e) {
        if(image)[context deleteObject:image];
        pgDiagnostic(@"Cover CoreData registration failed %@: %@",relationship,e.reason);
        return NO;
    }
}
static void pgSeedProducts(void) {
    if(pgSeedComplete || pgSeedAttemptRunning)return;
    pgLoadManifest();
    if (![pgEntriesByID count]) {pgDiagnostic(@"SEED FAILED: manifest empty");return;}
    pgSeedAttemptRunning=YES;
    Class databaseClass=NSClassFromString(@"Database");
    if (!databaseClass) {
        pgDiagnostic(@"SEED FAILED: original Database class not found");
        pgSeedAttemptRunning=NO;return;
    }
    if (![databaseClass respondsToSelector:@selector(sharedInstance)]) {
        pgDiagnostic(@"SEED FAILED: Database missing sharedInstance");
        pgSeedAttemptRunning=NO;return;
    }
    id database=pgMsg0((id)databaseClass,@selector(sharedInstance));
    if(!database) {pgDiagnostic(@"SEED FAILED: Database sharedInstance nil");pgSeedAttemptRunning=NO;return;}
    NSManagedObjectContext *context=pgMsg0(database,@selector(managedObjectContext));
    if(!context) {pgDiagnostic(@"SEED FAILED: Database context nil");pgSeedAttemptRunning=NO;return;}
    // Fast path for existing installations: a single COUNT instead of 63
    // fetches and image checks on every original iPad bookshelf load.
    NSFetchRequest *quickCount=[NSFetchRequest fetchRequestWithEntityName:@"Product"];
    [quickCount setPredicate:[NSPredicate predicateWithFormat:@"productID BEGINSWITH %@",@"pg.offline."]];
    NSError *quickError=nil;
    NSUInteger existing=[context countForFetchRequest:quickCount error:&quickError];
    if (!quickError && existing==[pgEntriesByID count]) {
        pgSeedComplete=YES;
        pgSeedAttemptRunning=NO;
        pgScheduleCoverMigration();
        return;
    }
    pgDiagnostic(@"Catalog recovery required: existing=%lu target=%lu error=%@",
                 (unsigned long)existing,(unsigned long)[pgEntriesByID count],
                 quickError?[quickError localizedDescription]:@"none");
    NSUInteger created=0, rejected=0;
    @try {
        // Core Data's original Product entity REQUIRES a Supplier relationship.
        // The v2 loader omitted it; validation error 1570 rejected all 63 rows.
        // Reuse an existing source publisher where appropriate, otherwise make
        // one stable, locally scoped publisher so retries remain idempotent.
        NSString *offlineSupplierID=@"pg.offline.publisher.ape";
        NSFetchRequest *supplierFetch=[NSFetchRequest fetchRequestWithEntityName:@"Supplier"];
        [supplierFetch setFetchLimit:1];
        [supplierFetch setPredicate:[NSPredicate predicateWithFormat:@"supplierID == %@",offlineSupplierID]];
        NSError *supplierError=nil;
        NSArray *supplierMatches=[context executeFetchRequest:supplierFetch error:&supplierError];
        if (supplierError) {
            pgDiagnostic(@"SEED supplier lookup failed: %@",supplierError);
            pgSeedAttemptRunning=NO;
            return;
        }
        NSManagedObject *offlineSupplier=nil;
        if ([supplierMatches count]) {
            offlineSupplier=[supplierMatches objectAtIndex:0];
        } else {
            offlineSupplier=[NSEntityDescription insertNewObjectForEntityForName:@"Supplier"
                                                           inManagedObjectContext:context];
            [offlineSupplier setValue:offlineSupplierID forKey:@"supplierID"];
            [offlineSupplier setValue:@"Ape Entertainment" forKey:@"name"];
            pgDiagnostic(@"SEED created required Supplier relationship: %@",offlineSupplierID);
        }
        if (!offlineSupplier) {
            pgDiagnostic(@"SEED supplier creation failed: nil object");
            [context rollback];
            pgSeedAttemptRunning=NO;
            return;
        }
        NSArray *keys=[[pgEntriesByID allKeys] sortedArrayUsingSelector:@selector(compare:)];
        for (NSString *identifier in keys) {
            NSDictionary *entry=[pgEntriesByID objectForKey:identifier];
            NSFetchRequest *fetch=[NSFetchRequest fetchRequestWithEntityName:@"Product"];
            [fetch setFetchLimit:1];
            [fetch setPredicate:[NSPredicate predicateWithFormat:@"productID == %@",identifier]];
            NSError *fetchError=nil;
            NSArray *matches=[context executeFetchRequest:fetch error:&fetchError];
            if(fetchError) {
                pgDiagnostic(@"SEED fetch error %@: %@",identifier,fetchError);
                rejected++;continue;
            }
            if([matches count])continue;
            NSManagedObject *product=nil;
            @try {
                product=[NSEntityDescription insertNewObjectForEntityForName:@"Product" inManagedObjectContext:context];
                [product setValue:identifier forKey:@"productID"];
                [product setValue:offlineSupplier forKey:@"supplier"];
                [product setValue:[entry objectForKey:@"title"] ?: identifier forKey:@"name"];
                [product setValue:identifier forKey:@"sortName"];
                [product setValue:[NSNumber numberWithInt:[[entry objectForKey:@"episode"] intValue]] forKey:@"number"];
                [product setValue:@"comic" forKey:@"productType"];
                [product setValue:[NSNumber numberWithBool:YES] forKey:@"completed"];
                [product setValue:[NSNumber numberWithInt:0] forKey:@"priceTier"];
                [product setValue:[NSNumber numberWithInt:0] forKey:@"lastPageRead"];
                [product setValue:[NSDate date] forKey:@"datePurchased"];
                [product setValue:[NSString stringWithFormat:@"PGOffline/%03d",[[entry objectForKey:@"episode"] intValue]] forKey:@"assetFilename"];
                [product setValue:@"Pocket God Comics — Offline Archive" forKey:@"synopsis"];
                created++;
            } @catch(NSException *e) {
                pgDiagnostic(@"SEED item failed %@: %@",identifier,e.reason);
                if(product) [context deleteObject:product];
                rejected++;
            }
        }
        NSError *saveError=nil;
        BOOL saved=!([context hasChanges]) || [context save:&saveError];
        if(!saved) {
            NSArray *details=[[saveError userInfo] objectForKey:NSDetailedErrorsKey];
            if ([details isKindOfClass:[NSArray class]] && [details count]) {
                NSMutableSet *fields=[NSMutableSet set];
                for (NSError *detail in details) {
                    id key=[[detail userInfo] objectForKey:NSValidationKeyErrorKey];
                    if(key)[fields addObject:key];
                }
                pgDiagnostic(@"SEED database save failed code=%ld, required keys=%@, violations=%lu",
                             (long)[saveError code],[fields allObjects],(unsigned long)[details count]);
            } else pgDiagnostic(@"SEED database save failed code=%ld %@",(long)[saveError code],[saveError localizedDescription]);
            [context rollback];
        } else {
            NSFetchRequest *check=[NSFetchRequest fetchRequestWithEntityName:@"Product"];
            [check setPredicate:[NSPredicate predicateWithFormat:@"productID BEGINSWITH %@",@"pg.offline."]];
            NSError *countError=nil;
            NSUInteger found=[context countForFetchRequest:check error:&countError];
            pgDiagnostic(@"SEED finished: new=%lu rejected=%lu offline rows=%lu of %lu countError=%@",
                         (unsigned long)created,(unsigned long)rejected,(unsigned long)found,
                         (unsigned long)[pgEntriesByID count],countError);
            if(!countError && found==[pgEntriesByID count]) {
                pgSeedComplete=YES;
                // The original app's aged CoreData image transformer can freeze
                // the UI when 63 covers are serialized synchronously.
                // The asynchronous 3-at-a-time migration seeds every missing
                // cover, updates 1-25 to genuine numbered issue artwork and
                // leaves fan-made cover art 26-35 intact.
                pgDiagnostic(@"Core products ready; defer cover setup in batches");
            }
        }
    } @catch(NSException *e) {
        pgDiagnostic(@"SEED exception: %@ %@",e.name,e.reason);
        [context rollback];
    }
    pgSeedAttemptRunning=NO;
    if(pgSeedComplete)pgScheduleCoverMigration();
}
static void pgDelayedSeed(void) {
    pgSeedProducts();
}
static void pgScheduleSeedRetry(void) {
    if (pgRetryScheduled)return;
    pgRetryScheduled=YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(2.0*NSEC_PER_SEC)),dispatch_get_main_queue(), ^{
        pgRetryScheduled=NO;
        pgDiagnostic(@"Deferred bookshelf seed check; ready=%d",pgSeedComplete);
        pgDelayedSeed();
    });
}

// Use original issue covers ONLY for the first 25 shelf positions of the
// existing 63-episode library. This is an index pairing, not a claim that one
// WEBTOON episode equals one historical printed issue.
static BOOL pgUpdateOriginalImageObject(id imageObject,UIImage *cover,BOOL alsoSmall) {
    if(!imageObject || !cover)return NO;
    @try {
        [imageObject setValue:cover forKey:@"image"];
        if(alsoSmall)[imageObject setValue:cover forKey:@"smallImage"];
        return YES;
    } @catch(NSException *e) {
        pgDiagnostic(@"Cover entity update failure: %@",e.reason);return NO;
    }
}
static void pgMigrateCoverBatch(void) {
    if (!pgCoverMigrationRunning || !pgCoverMigrationProducts) return;
    Class dbClass=NSClassFromString(@"Database");
    id db=dbClass?pgMsg0((id)dbClass,@selector(sharedInstance)):nil;
    NSManagedObjectContext *context=db?pgMsg0(db,@selector(managedObjectContext)):nil;
    if(!context) {
        pgDiagnostic(@"Original issue migration cancelled: no database context");
        pgCoverMigrationProducts=nil;pgCoverMigrationRunning=NO;return;
    }
    NSUInteger count=[pgCoverMigrationProducts count];
    NSUInteger stop=MIN(pgCoverMigrationIndex+3,count);
    BOOL valid=YES;
    @autoreleasepool {
        for(NSUInteger i=pgCoverMigrationIndex;i<stop;i++) {
            NSManagedObject *product=[pgCoverMigrationProducts objectAtIndex:i];
            NSString *pid=[product valueForKey:@"productID"];
            NSDictionary *entry=[pgEntriesByID objectForKey:pid];
            if(!entry)continue;
            // v8 persisted a migrated flag that is not reliable after app upgrades.
            // Rebuild ALL 63 tiny cover images on first v10 launch, and only
            // repair missing image entities/attributes on later launches.
            BOOL forceRepair= ![[NSUserDefaults standardUserDefaults]
                                 boolForKey:@"PGOfflineCoverCacheV10Migrated"];
            if(!forceRepair) {
                id currentCover=[product valueForKey:@"coverImage"];
                id currentThumb=[product valueForKey:@"thumbnailImage"];
                id currentShelf=[product valueForKey:@"shelfThumbnail"];
                if(currentCover && currentThumb && currentShelf) {
                    @try {
                        if([currentCover valueForKey:@"image"] &&
                           [currentThumb valueForKey:@"smallImage"] &&
                           [currentShelf valueForKey:@"image"])continue;
                    } @catch(NSException *e) {
                        pgDiagnostic(@"Cover validation exception: %@",e.reason);
                    }
                }
            }
            UIImage *thumb=pgShelfCover(entry);
            if(!thumb) {
                pgDiagnostic(@"Original cover missing %@",pid);
                valid=NO;break;
            }
            @try {
                id cover=[product valueForKey:@"coverImage"];
                id thumbnail=[product valueForKey:@"thumbnailImage"];
                id shelf=[product valueForKey:@"shelfThumbnail"];
                if(!cover) {
                    valid=pgAttachImage(context,product,@"ProductCover",@"coverImage",thumb);
                } else valid=pgUpdateOriginalImageObject(cover,thumb,NO);
                if(!valid)break;
                if(!thumbnail) {
                    valid=pgAttachImage(context,product,@"ProductThumbnail",@"thumbnailImage",thumb);
                } else valid=pgUpdateOriginalImageObject(thumbnail,thumb,YES);
                if(!valid)break;
                if(!shelf) {
                    valid=pgAttachImage(context,product,@"ShelfThumbnail",@"shelfThumbnail",thumb);
                } else valid=pgUpdateOriginalImageObject(shelf,thumb,NO);
                if(!valid)break;
            } @catch(NSException *e) {
                pgDiagnostic(@"Original cover migration exception %@: %@",pid,e.reason);
                valid=NO;break;
            }
        }
        NSError *error=nil;
        if(valid && [context hasChanges] && ![context save:&error])valid=NO;
        if(!valid) {
            pgDiagnostic(@"Original cover migration FAILED after %lu: %@",
                         (unsigned long)pgCoverMigrationIndex,error?[error localizedDescription]:@"entity error");
            [context rollback];
        }
    }
    if(!valid) {
        pgCoverMigrationProducts=nil;
        pgCoverMigrationRunning=NO;
        return; // leave user default unset; retry on next launch
    }
    pgCoverMigrationIndex=stop;
    // Keep UIKit responsive on older iPad: 3 thumbnails per runloop iteration.
    id currentShelf=pgVisibleIpadShelf;
    if(currentShelf && [currentShelf respondsToSelector:@selector(myComicsTableView)]) {
        id table=pgMsg0(currentShelf,@selector(myComicsTableView));
        if([table respondsToSelector:@selector(reloadData)])[table reloadData];
    }
    if(stop<count) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.18*NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{pgMigrateCoverBatch();});
    } else {
        pgCoverMigrationProducts=nil;
        pgCoverMigrationRunning=NO;
        NSUserDefaults *prefs=[NSUserDefaults standardUserDefaults];
        [prefs setBool:YES forKey:@"PGOfflineCoverCacheV10Migrated"];
        [prefs synchronize];
        pgDiagnostic(@"V10 COVER REPAIR COMPLETE: %lu comic shelf records repaired and checked",
                     (unsigned long)count);
    }
}
static void pgScheduleCoverMigration(void) {
    if(pgCoverMigrationRunning || !pgSeedComplete)return;
    // Never trust the old v8 flag; v9 could have empty cover records despite
    // that flag. Verify all current objects and heal partial reinstalls.
    Class dbClass=NSClassFromString(@"Database");
    id db=dbClass?pgMsg0((id)dbClass,@selector(sharedInstance)):nil;
    NSManagedObjectContext *context=db?pgMsg0(db,@selector(managedObjectContext)):nil;
    if(!context)return;
    NSFetchRequest *request=[NSFetchRequest fetchRequestWithEntityName:@"Product"];
    // Fetch all offline products in one query. Refresh authentic print slots
    // #1-25, and populate only MISSING covers for the other 38 entries.
    [request setPredicate:[NSPredicate predicateWithFormat:@"productID BEGINSWITH %@",@"pg.offline."]];
    [request setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"number" ascending:YES]]];
    NSError *error=nil;
    NSArray *products=[context executeFetchRequest:request error:&error];
    if(error || [products count]!=[pgEntriesByID count]) {
        pgDiagnostic(@"Original issue cover migration not ready: found=%lu/63 error=%@",
                     (unsigned long)[products count],error?[error localizedDescription]:@"none");
        return;
    }
    pgCoverMigrationProducts=[products copy];
    pgCoverMigrationIndex=0;
    pgCoverMigrationRunning=YES;
    pgDiagnostic(@"Original issue cover migration scheduled: 63 products, 3 per batch");
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.6*NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{pgMigrateCoverBatch();});
}
// iPad fallback retains original launch, too. Never invoke automatic shelf presentation.
static BOOL pgIpadLaunch(id self,SEL cmd,id app,id options) {
    BOOL ok=((BOOL (*)(id,SEL,id,id))pgOrigIpadLaunch)(self,cmd,app,options);
    pgSeedProducts();
    pgScheduleSeedRetry();
    return ok;
}
// RESTORED: original iVerse iPhone decides which tab to show on launch.
static BOOL pgPhoneLaunch(id self,SEL cmd,id app,id options) {
    pgDiagnostic(@"iPhone original launch path, no automatic tab switching");
    BOOL ok=((BOOL (*)(id,SEL,id,id))pgOrigPhoneLaunch)(self,cmd,app,options);
    pgSeedProducts();
    pgScheduleSeedRetry();
    return ok;
}
// Connect existing verified Core Data Product records to the original iVerse iPad
// shelf's separate mutable product list. Keep original products and original UI.
static void pgPopulateIpadShelf(id shelf) {
    Class c=NSClassFromString(@"Database");
    id db=c?pgMsg0((id)c,@selector(sharedInstance)):nil;
    NSManagedObjectContext *context=db?pgMsg0(db,@selector(managedObjectContext)):nil;
    if(!context){pgDiagnostic(@"SHELF no managed context");return;}
    NSFetchRequest *req=[NSFetchRequest fetchRequestWithEntityName:@"Product"];
    [req setPredicate:[NSPredicate predicateWithFormat:@"productID BEGINSWITH %@",@"pg.offline."]];
    [req setSortDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"number" ascending:YES]]];
    NSError *error=nil;
    NSArray *saved=[context executeFetchRequest:req error:&error];
    id original=pgMsg0(shelf,@selector(productList));
    NSUInteger originalCount=[original respondsToSelector:@selector(count)]?[original count]:0;
    pgDiagnostic(@"SHELF original list=%@ count=%lu, saved offline=%lu, fetch error=%@",
                 NSStringFromClass([original class]),(unsigned long)originalCount,
                 (unsigned long)[saved count],error?[error localizedDescription]:@"none");
    if(error || ![saved count])return;
    NSMutableArray *merged=[NSMutableArray array];
    NSMutableSet *ids=[NSMutableSet set];
    if([original isKindOfClass:[NSArray class]]){
        for(id product in (NSArray *)original){
            if(![product isKindOfClass:[NSManagedObject class]])continue;
            [merged addObject:product];
            id identifier=[product valueForKey:@"productID"];
            if(identifier)[ids addObject:identifier];
        }
    }
    NSUInteger added=0;
    for(NSManagedObject *product in saved){
        id identifier=[product valueForKey:@"productID"];
        if(!identifier || [ids containsObject:identifier])continue;
        [merged addObject:product];
        [ids addObject:identifier];
        added++;
    }
    if(!added){pgDiagnostic(@"SHELF original array already has every offline entry");return;}
    @try {
        pgMsg1(shelf,@selector(setProductList:),merged);
        id table=pgMsg0(shelf,@selector(myComicsTableView));
        if([table respondsToSelector:@selector(reloadData)])[table reloadData];
        pgDiagnostic(@"SHELF merged %lu offline entries; productList count=%lu; table=%@",
                     (unsigned long)added,(unsigned long)[merged count],
                     NSStringFromClass([table class]));
    } @catch(NSException *exception) {
        pgDiagnostic(@"SHELF merge exception: %@",exception.reason);
    }
}
static void pgIpadLoad(id self,SEL cmd) {
    pgVisibleIpadShelf=self;
    pgDiagnostic(@"iPad original loadProducts hook; seedReady=%d",pgSeedComplete);
    pgSeedProducts();
    ((void (*)(id,SEL))pgOrigIpadLoad)(self,cmd);
    pgPopulateIpadShelf(self);
} 
static void pgPhoneLoadShelf(id self,SEL cmd) {
    // IMPORTANT: original phone My Comics library uses loadShelfView,
    // while iPad uses ShelfViewController_iPad -loadProducts.
    pgDiagnostic(@"IPHONE original loadShelfView; seedReady=%d",pgSeedComplete);
    pgSeedProducts();
    ((void(*)(id,SEL))pgOrigPhoneLoadShelf)(self,cmd);
    // Let the original UI load its own Database productsByName and reload data.
}
static void pgPhoneAppear(id self,SEL cmd,BOOL animated) {
    pgSeedProducts();
    ((void (*)(id,SEL,BOOL))pgOrigPhoneAppear)(self,cmd,animated);
    // The original implementation is a no-op. Refresh from CoreData when tab
    // reappears, but do not do repeated work inside the reader.
    if(pgSeedComplete && [self respondsToSelector:@selector(loadShelfView)]) {
        pgMsg0(self,@selector(loadShelfView));
    }
}
// The ORIGINAL iPad shelf calls ComicBundle -initWithFileAtPath: when opening.
// The earlier offline bridge only patched -initWithProduct:, so it never
// handled that route. The reader subsequently rejected the missing old-format
// file and deleted the offline product.
static NSDictionary *pgEntryForAssetPath(id assetPath) {
    if (![assetPath isKindOfClass:[NSString class]])return nil;
    NSString *path=(NSString *)assetPath;
    NSRange marker=[path rangeOfString:@"PGOffline/" options:NSBackwardsSearch];
    if (marker.location==NSNotFound)return nil;
    NSString *tail=[path substringFromIndex:marker.location+marker.length];
    if ([tail length]<3)return nil;
    NSString *three=[tail substringToIndex:3];
    NSCharacterSet *nonDigits=[[NSCharacterSet decimalDigitCharacterSet] invertedSet];
    if ([three rangeOfCharacterFromSet:nonDigits].location!=NSNotFound)return nil;
    if ([tail length]>3) {
        unichar next=[tail characterAtIndex:3];
        if(next!='/' && next!='.')return nil;
    }
    return [pgEntriesByID objectForKey:[NSString stringWithFormat:@"pg.offline.%@",three]];
}
static id pgInitOfflineBundle(id self,NSDictionary *entry,id product) {
    id obj=pgMsg0(self,@selector(init));
    if(!obj) {
        pgDiagnostic(@"READER failed: original ComicBundle init returned nil");
        return nil;
    }
    SEL common=NSSelectorFromString(@"commonInit");
    if([obj respondsToSelector:common])pgMsg0(obj,common);
    objc_setAssociatedObject(obj,PGEntryKey,entry,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    SEL setProduct=NSSelectorFromString(@"setProduct:");
    if(product && [obj respondsToSelector:setProduct])pgMsg1(obj,setProduct,product);
    SEL setName=NSSelectorFromString(@"setName:");
    if([obj respondsToSelector:setName])pgMsg1(obj,setName,[entry objectForKey:@"title"]);
    pgDiagnostic(@"READER locally initialized episode %03d; source pages=%lu",
       [[entry objectForKey:@"episode"] intValue],
       (unsigned long)[[entry objectForKey:@"pages"] count]);
    return obj;
}
static id pgBundleFromFilePath(id self,SEL cmd,id path) {
    NSDictionary *entry=pgEntryForAssetPath(path);
    if(entry){
        pgDiagnostic(@"READER intercept original initWithFileAtPath: %@",path);
        return pgInitOfflineBundle(self,entry,nil);
    }
    pgDiagnostic(@"READER pass-through original initWithFileAtPath: %@",path);
    return ((id (*)(id,SEL,id))pgOrigBundleFilePath)(self,cmd,path);
}
static void pgPreventOfflineDeletion(id self,SEL cmd,id product) {
    NSDictionary *entry=pgEntryForProduct(product);
    if(entry){
       pgDiagnostic(@"READER blocked automatic deletion of offline episode %03d after failed open",
          [[entry objectForKey:@"episode"] intValue]);
       return;
    }
    ((void (*)(id,SEL,id))pgOrigRemoveProduct)(self,cmd,product);
}
static id pgBundleInit(id self,SEL cmd,id product) {
    NSDictionary *entry=pgEntryForProduct(product);
    if(!entry)return ((id (*)(id,SEL,id))pgOrigBundleInit)(self,cmd,product);
    id obj=pgMsg0(self,@selector(init));
    if(obj) {
        SEL common=NSSelectorFromString(@"commonInit");
        if([obj respondsToSelector:common])pgMsg0(obj,common);
        objc_setAssociatedObject(obj, PGEntryKey,entry,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        SEL setProduct=NSSelectorFromString(@"setProduct:");
        if([obj respondsToSelector:setProduct])pgMsg1(obj,setProduct,product);
        SEL setName=NSSelectorFromString(@"setName:");
        if([obj respondsToSelector:setName])pgMsg1(obj,setName,[entry objectForKey:@"title"]);
        SEL setComic=NSSelectorFromString(@"setComicID:");
        if([obj respondsToSelector:setComic])pgMsg1(obj,setComic,[product valueForKey:@"productID"]);
    }
    return obj;
}
static short pgVerticalCount(id self,SEL cmd) {
    NSDictionary *e=pgEntryForBundle(self);
    return e?(short)[[e objectForKey:@"pages"] count]:((short (*)(id,SEL))pgOrigBundleVertical)(self,cmd);
}
static short pgHorizontalCount(id self,SEL cmd) {
    NSDictionary *e=pgEntryForBundle(self);
    return e?(short)[[e objectForKey:@"pages"] count]:((short (*)(id,SEL))pgOrigBundleHorizontal)(self,cmd);
}
static id pgBundleImage(id self,SEL cmd,int index) {
    NSDictionary *e=pgEntryForBundle(self);
    return e?pgPage(e,index):((id(*)(id,SEL,int))pgOrigBundleImage)(self,cmd,index);
}
static id pgBundleVerticalImage(id self,SEL cmd,int index) {
    NSDictionary *e=pgEntryForBundle(self);
    return e?pgPage(e,index):((id(*)(id,SEL,int))pgOrigBundleVerticalImage)(self,cmd,index);
}
static id pgBundleForcedImage(id self,SEL cmd,int index) {
    NSDictionary *e=pgEntryForBundle(self);
    return e?pgPage(e,index):((id(*)(id,SEL,int))pgOrigBundleForcedImage)(self,cmd,index);
}
static id pgBundleCover(id self,SEL cmd) {
    NSDictionary *e=pgEntryForBundle(self);
    return e?pgCover(e):((id(*)(id,SEL))pgOrigBundleCover)(self,cmd);
}
static BOOL pgBundleAuthentic(id self,SEL cmd) {
    return pgEntryForBundle(self)?YES:((BOOL(*)(id,SEL))pgOrigBundleAuthentic)(self,cmd);
}
static BOOL pgBundleChecksum(id self,SEL cmd) {
    return pgEntryForBundle(self)?YES:((BOOL(*)(id,SEL))pgOrigBundleChecksum)(self,cmd);
}
static int pgVertIndex(id self,SEL cmd,int index) {
    return pgEntryForBundle(self)?index:((int(*)(id,SEL,int))pgOrigBundleVertIndex)(self,cmd,index);
}
static int pgHorizIndex(id self,SEL cmd,int index) {
    return pgEntryForBundle(self)?index:((int(*)(id,SEL,int))pgOrigBundleHorizIndex)(self,cmd,index);
}
static BOOL pgProductInstalled(id self,SEL cmd,id product) {
    return pgEntryForProduct(product)?YES:((BOOL(*)(id,SEL,id))pgOrigProductInstalled)(self,cmd,product);
}
static void pgHook(Class cls,SEL sel,IMP imp,IMP *old) {
    if(!cls)return;
    Method method=class_getInstanceMethod(cls,sel);
    if(method) {
        *old=method_setImplementation(method,imp);
        pgDiagnostic(@"Hooked %s %s",class_getName(cls),sel_getName(sel));
    } else pgDiagnostic(@"Missing selector: %s",sel_getName(sel));
}
__attribute__((constructor)) static void pgInstallHooks(void) {
    @autoreleasepool {
        pgDiagnostic(@"Offline content bridge dynamic library loaded; loaderVersion=13.0-UNIVERSAL-ORIGINAL-START");
        pgLoadManifest();
        Class bundle=NSClassFromString(@"ComicBundle"),database=NSClassFromString(@"Database");
        pgHook(bundle,@selector(initWithProduct:),(IMP)pgBundleInit,&pgOrigBundleInit);
        pgHook(bundle,@selector(initWithFileAtPath:),(IMP)pgBundleFromFilePath,&pgOrigBundleFilePath);
        pgHook(bundle,@selector(verticalPanelCount),(IMP)pgVerticalCount,&pgOrigBundleVertical);
        pgHook(bundle,@selector(horizontalPanelCount),(IMP)pgHorizontalCount,&pgOrigBundleHorizontal);
        pgHook(bundle,@selector(imageForPanel:),(IMP)pgBundleImage,&pgOrigBundleImage);
        pgHook(bundle,@selector(verticalImageForPanel:),(IMP)pgBundleVerticalImage,&pgOrigBundleVerticalImage);
        pgHook(bundle,@selector(forceVerticalImageForPanel:),(IMP)pgBundleForcedImage,&pgOrigBundleForcedImage);
        pgHook(bundle,@selector(verticalCoverImage),(IMP)pgBundleCover,&pgOrigBundleCover);
        pgHook(bundle,@selector(isAuthentic),(IMP)pgBundleAuthentic,&pgOrigBundleAuthentic);
        pgHook(bundle,@selector(checksumIsValid),(IMP)pgBundleChecksum,&pgOrigBundleChecksum);
        pgHook(bundle,@selector(verticalIndexForHorizontalPanelIndex:),(IMP)pgVertIndex,&pgOrigBundleVertIndex);
        pgHook(bundle,@selector(horizontalIndexForVerticalPanelIndex:),(IMP)pgHorizIndex,&pgOrigBundleHorizIndex);
        pgHook(database,@selector(productIsInstalled:),(IMP)pgProductInstalled,&pgOrigProductInstalled);
        pgHook(database,@selector(removeProductFromCollection:),(IMP)pgPreventOfflineDeletion,&pgOrigRemoveProduct);
        pgHook(NSClassFromString(@"iVerse_ReaderiPadAppDelegate"),@selector(application:didFinishLaunchingWithOptions:),(IMP)pgIpadLaunch,&pgOrigIpadLaunch);
        pgHook(NSClassFromString(@"iVerse_ReaderAppDelegate"),@selector(application:didFinishLaunchingWithOptions:),(IMP)pgPhoneLaunch,&pgOrigPhoneLaunch);
        pgHook(NSClassFromString(@"ShelfViewController_iPad"),@selector(loadProducts),(IMP)pgIpadLoad,&pgOrigIpadLoad);
        pgHook(NSClassFromString(@"MyComicsViewController"),@selector(loadShelfView),(IMP)pgPhoneLoadShelf,&pgOrigPhoneLoadShelf);
        pgHook(NSClassFromString(@"MyComicsViewController"),@selector(viewDidAppear:),(IMP)pgPhoneAppear,&pgOrigPhoneAppear);
    }
}
