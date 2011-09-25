/*
 Copyright 2010 Microsoft Corp
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 */

#import "TableListController.h"
#import "Azure_Storage_ClientAppDelegate.h"
#import "CreateTableController.h"
#import "EntityListController.h"
#import "BlobViewerController.h"
#import "UIViewController+ShowError.h"
#import "WAConfiguration.h"

#import "WAAuthenticationCredential.h"
#import "WABlobContainer.h"
#import "WABlob.h"
#import "WAQueue.h"
#import "WAResultContinuation.h"
#import "WAQueue.h"

#define MAX_ROWS 5

#define ENTITY_TYPE_TABLE 1
#define ENTITY_TYPE_QUEUE 2

typedef enum {
	TableStorage,
	QueueStorage,
	BlobStorage,
	BlobList
} StorageType;

@interface TableListController()

- (BOOL)canModify;
- (StorageType)storageType;
- (void)fetchData;

@end

@implementation TableListController

@synthesize selectedContainer;
@synthesize selectedQueue;
@synthesize resultContinuation = _resultContinuation;
@synthesize localStorageList = _localStorageList;

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        
    }
    return self;
}

- (void)dealloc
{
    storageClient.delegate = nil;
    RELEASE(storageClient);
    RELEASE(selectedContainer);
    RELEASE(selectedQueue);
    RELEASE(_resultContinuation);
    RELEASE(_localStorageList);
    
    [super dealloc];
}

- (void)didReceiveMemoryWarning
{
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}

#pragma mark - View lifecycle

- (void)viewDidLoad
{
    [super viewDidLoad];

	storageClient = nil;

	if([self canModify])
	{
		self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(modifyStorage:)] autorelease];
	}
    _localStorageList = [[NSMutableArray alloc] initWithCapacity:20];
}

- (void)viewDidUnload
{   
    [super viewDidUnload];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    Azure_Storage_ClientAppDelegate *appDelegate = (Azure_Storage_ClientAppDelegate *)[[UIApplication sharedApplication] delegate];
	
	if (storageClient) {
        storageClient.delegate = nil;
		[storageClient release];
	}
	
	storageClient = [[WACloudStorageClient storageClientWithCredential:appDelegate.authenticationCredential] retain];
	storageClient.delegate = self;
	
    if (self.localStorageList.count == 0) {
        [self fetchData];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    storageClient.delegate = nil;
    
    [super viewWillDisappear:animated];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}

#pragma mark - Action Methods

- (IBAction)modifyStorage:(id)sender
{
	CreateTableController *newController = [[CreateTableController alloc] initWithNibName:@"CreateTableController" bundle:nil];
	
	switch ([self storageType]) {
		case TableStorage: {
			newController.navigationItem.title = @"Create Table";
			break;
		}
			
		case QueueStorage: {
			newController.navigationItem.title = @"Create Queue";
			break;
		}
			
		case BlobStorage: {
			newController.navigationItem.title = @"Create Container";
			break;
		}
			
		default: {
			if (self.selectedContainer) {
				newController.navigationItem.title = @"Create Blob";
				newController.selectedContainer = self.selectedContainer;
			} else if (self.selectedQueue) {
				newController.navigationItem.title = @"Create Queue";
				newController.selectedQueue = self.selectedQueue;
			}
			break;
		}
	}
	
	[self.navigationController pushViewController:newController animated:YES];
	[newController release];
}

#pragma mark - Private Methods

- (StorageType)storageType
{
	if ([self.navigationItem.title isEqualToString:@"Table Storage"]) {
		return TableStorage;
	} else if ([self.navigationItem.title isEqualToString:@"Queue Storage"]) {
		return QueueStorage;
	} else if ([self.navigationItem.title isEqualToString:@"Blob Storage"]) {
		return BlobStorage;
	} else {
		return BlobList;
	}
}

- (BOOL)canModify
{
	WAConfiguration *config = [WAConfiguration sharedConfiguration];
	
	switch([self storageType]) {
		case TableStorage: {
			return YES;
		}
			
		case QueueStorage: {
			return YES;
		}
			
		case BlobStorage: {
			return (config.connectionType == WAConnectDirect);
		}
			
		default: {
			return (self.selectedContainer != nil);
		}
	}
}

- (void)fetchData
{
    switch([self storageType]) {
		case TableStorage: {
            [storageClient fetchTablesSegmented:self.resultContinuation];
            break;
        }
        case QueueStorage: {
            [storageClient fetchQueuesSegmented:self.resultContinuation maxResult:MAX_ROWS];
            //[storageClient fetchQueues];
            break;
        }
        case BlobStorage: {
            [storageClient fetchBlobContainersSegmented:self.resultContinuation maxResult:MAX_ROWS];
            break;
        }
        default: {
            WABlobContainer *container = [[WABlobContainer alloc] initContainerWithName:self.navigationItem.title];
            [storageClient fetchBlobsSegmented:container resultContinuation:self.resultContinuation maxResult:MAX_ROWS];
            [container release];
            break;
        }
    }
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSUInteger count = fetchCount; 
    NSUInteger localCount = self.localStorageList.count;
    
    if (count >= MAX_ROWS) {
        localCount += 1;
    }
    
    return localCount;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"Cell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier] autorelease];
	}
    
    if (indexPath.row != self.localStorageList.count) {
        switch([self storageType]) {
            case TableStorage: {
                cell.textLabel.text = [self.localStorageList objectAtIndex:indexPath.row];
                break;
            }
            case QueueStorage: {
                WAQueue *queue = [self.localStorageList objectAtIndex:indexPath.row];
                cell.textLabel.text = queue.queueName;
                break;
            }
            case BlobStorage: {
                WABlobContainer *container = [self.localStorageList objectAtIndex:indexPath.row];
                cell.textLabel.text = container.name;
                break;
            }
            default: {
                WABlob *blob = [self.localStorageList objectAtIndex:indexPath.row];
                cell.textLabel.text = blob.name;
                break;
            }
        }
    }

    if (indexPath.row == self.localStorageList.count) {
        if (fetchCount == MAX_ROWS) {
            UITableViewCell *loadMoreCell = [tableView dequeueReusableCellWithIdentifier:@"LoadMore"];
            if (loadMoreCell == nil) {
                loadMoreCell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"LoadMore"] autorelease];
            }
            
            UILabel *loadMore =[[UILabel alloc] initWithFrame:CGRectMake(0,0,362,40)];
            loadMore.textColor = [UIColor blackColor];
            loadMore.highlightedTextColor = [UIColor darkGrayColor];
            loadMore.backgroundColor = [UIColor clearColor];
            loadMore.textAlignment = UITextAlignmentCenter;
            loadMore.font = [UIFont boldSystemFontOfSize:20];
            loadMore.text = @"Show more results...";
            [loadMoreCell addSubview:loadMore];
            [loadMore release];
            return loadMoreCell;
        }
    }
    return cell;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    if (fetchCount == MAX_ROWS && indexPath.row == self.localStorageList.count) {
        [tableView beginUpdates];
        fetchCount--;
        [self.tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] 
                              withRowAnimation:UITableViewScrollPositionBottom];
        [tableView endUpdates];
        [self fetchData];
        return;
    }
    
	if ([self.navigationItem.title isEqualToString:@"Table Storage"]) {
        EntityListController *newController = [[EntityListController alloc] initWithNibName:@"EntityListController" bundle:nil];
		
        newController.navigationItem.title = [self.localStorageList objectAtIndex:indexPath.row];
        newController.entityType = ENTITY_TYPE_TABLE;
        [self.navigationController pushViewController:newController animated:YES];
        [newController release];
       
	} else if ([self.navigationItem.title isEqualToString:@"Queue Storage"]) {
		EntityListController *newController = [[EntityListController alloc] initWithNibName:@"EntityListController" bundle:nil];
		WAQueue *queue = [self.localStorageList objectAtIndex:indexPath.row];
		
		newController.navigationItem.title = queue.queueName;
		newController.entityType = ENTITY_TYPE_QUEUE;
		[self.navigationController pushViewController:newController animated:YES];
		[newController release];
	} else if ([self.navigationItem.title isEqualToString:@"Blob Storage"]) {
        TableListController *newController = [[TableListController alloc] initWithNibName:@"TableListController" bundle:nil];
		
        newController.selectedContainer = [self.localStorageList objectAtIndex:indexPath.row];
        newController.navigationItem.title = newController.selectedContainer.name;
        [self.navigationController pushViewController:newController animated:YES];
        [newController release];
	} else {
        BlobViewerController *newController = [[BlobViewerController alloc] initWithNibName:@"BlobViewerController" bundle:nil];
        WABlob *blob = [self.localStorageList objectAtIndex:indexPath.row];
		
        newController.navigationItem.title = blob.name;
        newController.blob = blob;
        [self.navigationController pushViewController:newController animated:YES];
        [newController release];
        
	}
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (fetchCount == MAX_ROWS && indexPath.row == self.localStorageList.count) {
        return NO;
    }

	return [self canModify];
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
	void(^block)(NSError*, NSString*) = ^(NSError* error, NSString* title) {
		self.tableView.allowsSelection = YES;
		self.navigationItem.backBarButtonItem.enabled = YES;
		self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd 
																								target:self 
																								action:@selector(modifyStorage:)] autorelease];
		
		if(error) {
			[self showError:error withTitle:title];
			return;
		}
		
		[self.localStorageList removeObjectAtIndex:indexPath.row];
		[tableView deleteRowsAtIndexPaths:[NSArray arrayWithObject:indexPath] 
						 withRowAnimation:UITableViewScrollPositionBottom];
	};
	
	self.tableView.allowsSelection = NO;
	self.navigationItem.backBarButtonItem.enabled = NO;
	
	UIActivityIndicatorView *view = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
	self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithCustomView:view] autorelease];
	[view startAnimating];
	[view release];
    
	switch([self storageType]) {
		case TableStorage: {
			[storageClient deleteTableNamed:[self.localStorageList objectAtIndex:indexPath.row] withCompletionHandler:^(NSError* error) {
				block(error, @"Error Deleting Table");
			}];
			break;
		}
			
		case QueueStorage: {
			WAQueue *queue = [self.localStorageList objectAtIndex:indexPath.row];
			[storageClient deleteQueueNamed:queue.queueName withCompletionHandler:^(NSError* error) {
				block(error, @"Error Deleting Queue");
			}];
			break;
		}
			
		case BlobStorage: {
			[storageClient deleteBlobContainer:[self.localStorageList objectAtIndex:indexPath.row] withCompletionHandler:^(NSError* error) {
				 block(error, @"Error Deleting Container");
			 }];
			break;
		}
			
		default: {
			[storageClient deleteBlob:[self.localStorageList objectAtIndex:indexPath.row] withCompletionHandler:^(NSError* error) {
				 block(error, @"Error Deleting Block");
			 }];
			break;
		}
	}
}

#pragma mark - CloudStorageClientDelegate Methods

- (void)storageClient:(WACloudStorageClient *)client didFailRequest:request withError:error
{
	[self showError:error];
}

- (void)storageClient:(WACloudStorageClient *)client didFetchTables:(NSArray *)tables withResultContinuation:(WAResultContinuation *)resultContinuation
{
    fetchCount = [tables count];
    self.resultContinuation = resultContinuation;
    [self.localStorageList addObjectsFromArray:tables];
	[self.tableView reloadData];
}

- (void)storageClient:(WACloudStorageClient *)client didFetchBlobContainers:(NSArray *)containers withResultContinuation:(WAResultContinuation *)resultContinuation
{
    fetchCount = [containers count];
    self.resultContinuation = resultContinuation;
    [self.localStorageList addObjectsFromArray:containers];
	[self.tableView reloadData];
}

- (void)storageClient:(WACloudStorageClient *)client didFetchBlobs:(NSArray *)blobs inContainer:(WABlobContainer *)container withResultContinuation:(WAResultContinuation *)resultContinuation
{
    fetchCount = [blobs count];
    self.resultContinuation = resultContinuation;
    [self.localStorageList addObjectsFromArray:blobs];
	[self.tableView reloadData];
}

- (void)storageClient:(WACloudStorageClient *)client didFetchQueues:(NSArray *)queues withResultContinuation:(WAResultContinuation *)resultContinuation
{
    fetchCount = [queues count];
    self.resultContinuation = resultContinuation;
    [self.localStorageList addObjectsFromArray:queues];
	[self.tableView reloadData];
}

/*
- (void)storageClient:(WACloudStorageClient *)client didFetchQueues:(NSArray *)queues 
{
    fetchCount = [queues count];
    //self.resultContinuation = resultContinuation;
    [self.localStorageList addObjectsFromArray:queues];
	[self.tableView reloadData];
}
*/
@end
