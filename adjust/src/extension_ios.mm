#if defined(DM_PLATFORM_IOS)

#import <AdjustSdk/Adjust.h>
#import <AdjustSdk/ADJDeeplink.h>
#import <AdjustSdk/ADJAdRevenue.h>
#import <AdjustSdk/ADJAttribution.h>
#include "extension.h"

#import "ios/utils.h"

#define ExtensionInterface FUNCTION_NAME_EXPANDED(EXTENSION_NAME, ExtensionInterface)

// Using proper Objective-C object for main extension entity.
@interface ExtensionInterface : NSObject <AdjustDelegate>
@end

@implementation ExtensionInterface {
    bool is_initialized;
    LuaScriptListener *script_listener;
    NSMutableDictionary *latest_attribution;
    NSString *cached_adid;
    NSString *cached_idfa;
    NSString *cached_sdk_version;
}

static NSString *const ADJUST = @"adjust";
static NSString *const EVENT_PHASE = @"phase";
static NSString *const EVENT_INIT = @"init";
static NSString *const EVENT_IS_ERROR = @"is_error";
static NSString *const EVENT_ERROR_MESSAGE = @"error_message";

static ExtensionInterface *extension_instance;
int EXTENSION_INIT(lua_State *L) {return [extension_instance init_:L];}
int EXTENSION_TRACK_EVENT(lua_State *L) {return [extension_instance track_event:L];}
int EXTENSION_TRACK_AD_REVENUE(lua_State *L) {return [extension_instance track_ad_revenue:L];}
int EXTENSION_SET_SESSION_PARAMETERS(lua_State *L) {return [extension_instance set_session_parameters:L];}
int EXTENSION_ENABLE(lua_State *L) {return [extension_instance enable:L];}
int EXTENSION_DISABLE(lua_State *L) {return [extension_instance disable:L];}
int EXTENSION_SET_PUSHTOKEN(lua_State *L) {return [extension_instance set_pushtoken:L];}
int EXTENSION_SWITCH_TO_OFFLINE_MODE(lua_State *L) {return [extension_instance switch_to_offline_mode:L];}
int EXTENSION_SWITCH_BACK_TO_ONLINE_MODE(lua_State *L) {return [extension_instance switch_back_to_online_mode:L];}
int EXTENSION_PROCESS_DEEPLINK(lua_State *L) {return [extension_instance process_deeplink:L];}
int EXTENSION_GDPR_FORGET_ME(lua_State *L) {return [extension_instance gdpr_forget_me:L];}
int EXTENSION_GET_ATTRIBUTION(lua_State *L) {return [extension_instance get_attribution:L];}
int EXTENSION_GET_ADID(lua_State *L) {return [extension_instance get_adid:L];}
int EXTENSION_GET_AMAZON_AD_ID(lua_State *L) {return [extension_instance get_amazon_ad_id:L];}
int EXTENSION_GET_GOOGLE_AD_ID(lua_State *L) {return [extension_instance get_google_ad_id:L];}
int EXTENSION_GET_SDK_VERSION(lua_State *L) {return [extension_instance get_sdk_version:L];}
int EXTENSION_GET_IDFA(lua_State *L) {return [extension_instance get_idfa:L];}

-(id)init:(lua_State*)L {
	self = [super init];

    is_initialized = false;
	script_listener = [LuaScriptListener new];
    script_listener.listener = LUA_REFNIL;
	script_listener.script_instance = LUA_REFNIL;

	return self;
}

-(bool)check_is_initialized {
	if (is_initialized) {
		return true;
	} else {
		dmLogInfo("The extension is not initialized.");
		return false;
	}
}

# pragma mark - Lua functions -

// adjust.init(params)
-(int)init_:(lua_State*)L {
	[Utils check_arg_count:L count:1];
	if (is_initialized) {
		dmLogInfo("The extension is already initialized.");
		return 0;
	}

    Scheme *scheme = [[Scheme alloc] init];
	[scheme string:@"app_token"];
	[scheme boolean:@"is_sandbox"];
	[scheme table:@"app_secret"];
	[scheme number:@"app_secret.id"];
	[scheme number:@"app_secret.info1"];
	[scheme number:@"app_secret.info2"];
	[scheme number:@"app_secret.info3"];
	[scheme number:@"app_secret.info4"];
	[scheme string:@"default_tracker"];
	[scheme number:@"delay_start"];
	[scheme boolean:@"is_device_known"];
	[scheme boolean:@"event_buffering"];
	[scheme string:@"log_level"];
	[scheme string:@"sdk_prefix"];
	[scheme boolean:@"send_in_background"];
	[scheme string:@"user_agent"];
    [scheme function:@"listener"];

    Table *params = [[Table alloc] init:L index:1];
    [params parse:scheme];

	NSString *app_token = [params get_string_not_null:@"app_token"];
	bool is_sandbox = [params get_boolean:@"is_sandbox" default:false];
	NSNumber *secret_id = [params get_long:@"app_secret.id"];
	NSNumber *secret_info1 = [params get_long:@"app_secret.info1"];
	NSNumber *secret_info2 = [params get_long:@"app_secret.info2"];
	NSNumber *secret_info3 = [params get_long:@"app_secret.info3"];
	NSNumber *secret_info4 = [params get_long:@"app_secret.info4"];
	NSString *default_tracker = [params get_string:@"default_tracker"];
	double delay_start = [params get_double:@"delay_start" default:0];
	NSNumber *is_device_known = [params get_boolean:@"is_device_known"];
	NSNumber *event_buffering = [params get_boolean:@"event_buffering"];
	NSString *log_level = [params get_string:@"log_level"];
	NSString *sdk_prefix = [params get_string:@"sdk_prefix"];
	NSNumber *send_in_background = [params get_boolean:@"send_in_background"];
	NSString *user_agent = [params get_string:@"user_agent"];

	[Utils delete_ref_if_not_nil:script_listener.listener];
	[Utils delete_ref_if_not_nil:script_listener.script_instance];
    script_listener.listener = [params get_function:@"listener" default:LUA_REFNIL];
	dmScript::GetInstance(L);
	script_listener.script_instance = [Utils new_ref:L];

 ADJConfig *config = [[ADJConfig alloc] initWithAppToken:app_token environment:(is_sandbox ? ADJEnvironmentSandbox : ADJEnvironmentProduction) suppressLogLevel:true];

	if (default_tracker) {
		config.defaultTracker = default_tracker;
	}

	if (log_level) {
		ADJLogLevel l;
		if ([log_level isEqualToString:@"assert"]) {
			l = ADJLogLevelAssert;
		} else if ([log_level isEqualToString:@"debug"]) {
			l = ADJLogLevelDebug;
		} else if ([log_level isEqualToString:@"error"]) {
			l = ADJLogLevelError;
		} else if ([log_level isEqualToString:@"supress"]) {
			l = ADJLogLevelSuppress;
		} else if ([log_level isEqualToString:@"verbose"]) {
			l = ADJLogLevelVerbose;
		} else if ([log_level isEqualToString:@"warn"]) {
			l = ADJLogLevelWarn;
		} else {
			l = ADJLogLevelInfo;
		}
		[config setLogLevel:l];
	}

	if (sdk_prefix) {
		[config setSdkPrefix:sdk_prefix];
	}

	if (send_in_background && send_in_background.boolValue) {
		[config enableSendingInBackground];
	}
	
	[config setDelegate:self];

	[Adjust initSdk:config];

    // Prefetch common values via async getters to enable synchronous Lua getters.
    [Adjust adidWithCompletionHandler:^(NSString * _Nullable adid) {
        self->cached_adid = adid;
    }];
    [Adjust idfaWithCompletionHandler:^(NSString * _Nullable idfa) {
        self->cached_idfa = idfa;
    }];
    [Adjust sdkVersionWithCompletionHandler:^(NSString * _Nullable sdkVersion) {
        self->cached_sdk_version = sdkVersion;
    }];
	
    is_initialized = true;
    NSMutableDictionary *event = [Utils new_event:ADJUST];
    event[EVENT_PHASE] = EVENT_INIT;
    event[EVENT_IS_ERROR] = @((bool)false);
    [Utils dispatch_event:script_listener event:event];
	return 0;
}

// adjust.track_event(params)
-(int)track_event:(lua_State*)L {
	[Utils check_arg_count:L count:1];
	if (![self check_is_initialized]) {
		return 0;
	}

	Scheme *scheme = [[Scheme alloc] init];
	[scheme string:@"token"];
	[scheme number:@"revenue"];
	[scheme string:@"currency"];
	[scheme string:@"transaction_id"];
	[scheme string:@"callback_id"];
	[scheme table:@"callback_parameters"];
	[scheme string:@"callback_parameters.#"];
	[scheme table:@"partner_parameters"];
	[scheme string:@"partner_parameters.#"];

	Table *params = [[Table alloc] init:L index:1];
	[params parse:scheme];

	NSString *token = [params get_string_not_null:@"token"];
	NSNumber *revenue = [params get_double:@"revenue"];
	NSString *currency = [params get_string:@"currency"];
	NSString *transaction_id = [params get_string:@"transaction_id"];
	NSString *callback_id = [params get_string:@"callback_id"];
	NSDictionary *callback_parameters = [params get_table:@"callback_parameters"];
	NSDictionary *partner_parameters = [params get_table:@"partner_parameters"];

	ADJEvent *event = [ADJEvent eventWithEventToken:token];

	if (revenue && currency) {
		[event setRevenue:revenue.doubleValue currency:currency];
		if (transaction_id) {
			[event setTransactionId:transaction_id];
		}
	}

	if (callback_id) {
		[event setCallbackId:callback_id];
	}

	if (callback_parameters) {
		for (id key in callback_parameters) {
			[event addCallbackParameter:(NSString*)key value:(NSString*)[callback_parameters objectForKey:key]];
		}
	}

	if (partner_parameters) {
		for (id key in partner_parameters) {
			[event addPartnerParameter:(NSString*)key value:(NSString*)[partner_parameters objectForKey:key]];
		}
	}

	[Adjust trackEvent:event];

	return 0;
}

// adjust.track_ad_revenue(params)
-(int)track_ad_revenue:(lua_State*)L {
	[Utils check_arg_count:L count:1];
	if (![self check_is_initialized]) {
		return 0;
	}

	Scheme *scheme = [[Scheme alloc] init];
	[scheme string:@"source"];
	[scheme number:@"revenue"];
	[scheme string:@"currency"];
	[scheme number:@"impressions_count"];
	[scheme string:@"network"];
	[scheme string:@"unit"];
	[scheme string:@"placement"];
	[scheme table:@"callback_parameters"];
	[scheme string:@"callback_parameters.#"];
	[scheme table:@"partner_parameters"];
	[scheme string:@"partner_parameters.#"];

	Table *params = [[Table alloc] init:L index:1];
	[params parse:scheme];

	NSString *source = [params get_string_not_null:@"source"];
	NSNumber *revenue = [params get_double:@"revenue"];
	NSString *currency = [params get_string:@"currency"];
	NSNumber *impressions = [params get_integer:@"impressions_count"];
	NSString *network = [params get_string:@"network"];
	NSString *unit = [params get_string:@"unit"];
	NSString *placement = [params get_string:@"placement"];
	NSDictionary *callback_parameters = [params get_table:@"callback_parameters"];
	NSDictionary *partner_parameters = [params get_table:@"partner_parameters"];

	ADJAdRevenue *adRevenue = [[ADJAdRevenue alloc] initWithSource:source];
	if (revenue && currency) {
		[adRevenue setRevenue:revenue.doubleValue currency:currency];
	}
	if (impressions) {
		[adRevenue setAdImpressionsCount:impressions.intValue];
	}
	if (network) {
		[adRevenue setAdRevenueNetwork:network];
	}
	if (unit) {
		[adRevenue setAdRevenueUnit:unit];
	}
	if (placement) {
		[adRevenue setAdRevenuePlacement:placement];
	}
	if (callback_parameters) {
		for (id key in callback_parameters) {
			[adRevenue addCallbackParameter:(NSString*)key value:(NSString*)[callback_parameters objectForKey:key]];
		}
	}
	if (partner_parameters) {
		for (id key in partner_parameters) {
			[adRevenue addPartnerParameter:(NSString*)key value:(NSString*)[partner_parameters objectForKey:key]];
		}
	}
	[Adjust trackAdRevenue:adRevenue];
	return 0;
}

// adjust.set_session_parameters(params)
-(int)set_session_parameters:(lua_State*)L {
	[Utils check_arg_count:L count:1];
	if (![self check_is_initialized]) {
		return 0;
	}

	Scheme *scheme = [[Scheme alloc] init];
	[scheme table:@"callback_parameters"];
	[scheme string:@"callback_parameters.#"];
	[scheme table:@"partner_parameters"];
	[scheme string:@"partner_parameters.#"];

	Table *params = [[Table alloc] init:L index:1];
	[params parse:scheme];

	NSDictionary *callback_parameters = [params get_table:@"callback_parameters"];
	NSDictionary *partner_parameters = [params get_table:@"partner_parameters"];

	if (callback_parameters) {
		[Adjust removeGlobalCallbackParameters];
		for (id key in callback_parameters) {
			[Adjust addGlobalCallbackParameter:(NSString*)[callback_parameters objectForKey:key] forKey:(NSString*)key];
		}
	}

	if (partner_parameters) {
		[Adjust removeGlobalPartnerParameters];
		for (id key in partner_parameters) {
			[Adjust addGlobalPartnerParameter:(NSString*)[partner_parameters objectForKey:key] forKey:(NSString*)key];
		}
	}

	return 0;
}

// adjust.enable()
-(int)enable:(lua_State*)L {
	[Utils check_arg_count:L count:0];
	if (![self check_is_initialized]) {
		return 0;
	}
	[Adjust enable];
	return 0;
}

// adjust.disable()
-(int)disable:(lua_State*)L {
	[Utils check_arg_count:L count:0];
	if (![self check_is_initialized]) {
		return 0;
	}
	[Adjust disable];
	return 0;
}

// adjust.set_pushtoken(token)
-(int)set_pushtoken:(lua_State*)L {
	[Utils check_arg_count:L count:1];
	if (![self check_is_initialized]) {
		return 0;
	}
	if (lua_isstring(L, 1)) {
		[Adjust setPushTokenAsString:@(lua_tostring(L, 1))];
	}
	return 0;
}

// adjust.switch_to_offline_mode()
-(int)switch_to_offline_mode:(lua_State*)L {
	[Utils check_arg_count:L count:0];
	if (![self check_is_initialized]) {
		return 0;
	}
	[Adjust switchToOfflineMode];
	return 0;
}

// adjust.switch_back_to_online_mode()
-(int)switch_back_to_online_mode:(lua_State*)L {
	[Utils check_arg_count:L count:0];
	if (![self check_is_initialized]) {
		return 0;
	}
	[Adjust switchBackToOnlineMode];
	return 0;
}

// adjust.process_deeplink(url)
-(int)process_deeplink:(lua_State*)L {
	[Utils check_arg_count:L count:1];
	if (![self check_is_initialized]) {
		return 0;
	}
	if (lua_isstring(L, 1)) {
		NSString *s = @(lua_tostring(L, 1));
		NSURL *url = [NSURL URLWithString:s];
		if (url) {
			ADJDeeplink *dl = [[ADJDeeplink alloc] initWithDeeplink:url];
			[Adjust processDeeplink:dl];
		}
	}
	return 0;
}

// adjust.gdpr_forget_me()
-(int)gdpr_forget_me:(lua_State*)L {
	[Utils check_arg_count:L count:0];
	if (![self check_is_initialized]) {
		return 0;
	}
	[Adjust gdprForgetMe];
	return 0;
}

// adjust.get_attribution(callback)
-(int)get_attribution:(lua_State*)L {
	[Utils check_arg_count:L count:1];
	if (![self check_is_initialized]) {
		return 0;
	}
	if (lua_isfunction(L, 1)) {
		LuaScriptListener *sl = [LuaScriptListener new];
		sl.listener = [Utils new_ref:L index:1];
		dmScript::GetInstance(L);
		sl.script_instance = [Utils new_ref:L];
  [Adjust attributionWithCompletionHandler:^(ADJAttribution * _Nullable attribution) {
			if (attribution == nil) {
				[Utils dispatch_event:sl event:nil delete_ref:true];
				return;
			}
			NSMutableDictionary *table = [NSMutableDictionary new];
			[Utils put:table key:@"adgroup" value:attribution.adgroup];
			[Utils put:table key:@"campaign" value:attribution.campaign];
			[Utils put:table key:@"click_label" value:attribution.clickLabel];
			[Utils put:table key:@"creative" value:attribution.creative];
			[Utils put:table key:@"network" value:attribution.network];
			[Utils put:table key:@"tracker_name" value:attribution.trackerName];
			[Utils put:table key:@"tracker_token" value:attribution.trackerToken];
			[Utils dispatch_event:sl event:table delete_ref:true];
		}];
	}
	return 0;
}

// adjust.get_adid(callback)
-(int)get_adid:(lua_State*)L {
	[Utils check_arg_count:L count:1];
	if (![self check_is_initialized]) {
		return 0;
	}
	if (lua_isfunction(L, 1)) {
		LuaScriptListener *sl = [LuaScriptListener new];
		sl.listener = [Utils new_ref:L index:1];
		dmScript::GetInstance(L);
		sl.script_instance = [Utils new_ref:L];
		[Adjust adidWithCompletionHandler:^(NSString * _Nullable adid) {
			[Utils dispatch_event:sl event:(adid ? (NSObject*)adid : (NSObject*)nil) delete_ref:true];
		}];
	}
	return 0;
}

// adjust.get_amazon_ad_id(callback)
-(int)get_amazon_ad_id:(lua_State*)L {
	[Utils check_arg_count:L count:1];
	if (![self check_is_initialized]) {
		return 0;
	}
	if (lua_isfunction(L, 1)) {
		LuaScriptListener *sl = [LuaScriptListener new];
		sl.listener = [Utils new_ref:L index:1];
		dmScript::GetInstance(L);
		sl.script_instance = [Utils new_ref:L];
		// Not available on iOS; dispatch nil to callback to mirror Android signature presence.
		[Utils dispatch_event:sl event:nil delete_ref:true];
	}
	return 0;
}

// adjust.get_google_ad_id(callback)
-(int)get_google_ad_id:(lua_State*)L {
	[Utils check_arg_count:L count:1];
	if (![self check_is_initialized]) {
		return 0;
	}
	if (lua_isfunction(L, 1)) {
		LuaScriptListener *sl = [LuaScriptListener new];
		sl.listener = [Utils new_ref:L index:1];
		dmScript::GetInstance(L);
		sl.script_instance = [Utils new_ref:L];
		// Not available on iOS; dispatch nil to callback to keep API parity.
		[Utils dispatch_event:sl event:nil delete_ref:true];
	}
	return 0;
}

// adjust.get_sdk_version(callback)
-(int)get_sdk_version:(lua_State*)L {
	[Utils check_arg_count:L count:1];
	if (![self check_is_initialized]) {
		return 0;
	}
	if (lua_isfunction(L, 1)) {
		LuaScriptListener *sl = [LuaScriptListener new];
		sl.listener = [Utils new_ref:L index:1];
		dmScript::GetInstance(L);
		sl.script_instance = [Utils new_ref:L];
		[Adjust sdkVersionWithCompletionHandler:^(NSString * _Nullable sdkVersion) {
			[Utils dispatch_event:sl event:(sdkVersion ? (NSObject*)sdkVersion : (NSObject*)nil) delete_ref:true];
		}];
	}
	return 0;
}

// adjust.get_idfa()
-(int)get_idfa:(lua_State*)L {
	[Utils check_arg_count:L count:0];
	if (![self check_is_initialized]) {
		return 0;
	}
	if (cached_idfa) {
		lua_pushstring(L, cached_idfa.UTF8String);
		return 1;
	}
	return 0;
}

#pragma mark - AdjustDelegate -

-(void)adjustAttributionChanged:(nullable ADJAttribution *)attribution {
	NSMutableDictionary *event = [Utils new_event:ADJUST];
	event[EVENT_PHASE] = @"attribution_changed";
	event[EVENT_IS_ERROR] = @((bool)false);
	[Utils put:event key:@"adgroup" value:attribution.adgroup];
	[Utils put:event key:@"campaign" value:attribution.campaign];
	[Utils put:event key:@"click_label" value:attribution.clickLabel];
	[Utils put:event key:@"creative" value:attribution.creative];
	[Utils put:event key:@"network" value:attribution.network];
	[Utils put:event key:@"tracker_name" value:attribution.trackerName];
	[Utils put:event key:@"tracker_token" value:attribution.trackerToken];
	// Cache latest attribution for synchronous get_attribution call.
	latest_attribution = [event mutableCopy];
	[Utils dispatch_event:script_listener event:event];
}

-(void)adjustEventTrackingSucceeded:(nullable ADJEventSuccess *)eventSuccessResponseData {
	NSMutableDictionary *event = [Utils new_event:ADJUST];
	event[EVENT_PHASE] = @"event_tracking";
	event[EVENT_IS_ERROR] = @((bool)false);
	[Utils put:event key:@"callback_id" value:eventSuccessResponseData.callbackId];
	[Utils put:event key:@"adid" value:eventSuccessResponseData.adid];
	[Utils put:event key:@"event_token" value:eventSuccessResponseData.eventToken];
	[Utils put:event key:@"message" value:eventSuccessResponseData.message];
	[Utils put:event key:@"timestamp" value:eventSuccessResponseData.timestamp];
	[Utils dispatch_event:script_listener event:event];
}

-(void)adjustEventTrackingFailed:(nullable ADJEventFailure *)eventFailureResponseData {
	NSMutableDictionary *event = [Utils new_event:ADJUST];
	event[EVENT_PHASE] = @"event_tracking";
	event[EVENT_IS_ERROR] = @((bool)true);
	[Utils put:event key:@"callback_id" value:eventFailureResponseData.callbackId];
	[Utils put:event key:@"adid" value:eventFailureResponseData.adid];
	[Utils put:event key:@"event_token" value:eventFailureResponseData.eventToken];
	[Utils put:event key:@"message" value:eventFailureResponseData.message];
	[Utils put:event key:@"timestamp" value:eventFailureResponseData.timestamp];
	[Utils put:event key:@"will_retry" value:@(eventFailureResponseData.willRetry)];
	[Utils dispatch_event:script_listener event:event];
}

-(void)adjustSessionTrackingSucceeded:(nullable ADJSessionSuccess *)sessionSuccessResponseData {
	NSMutableDictionary *event = [Utils new_event:ADJUST];
	event[EVENT_PHASE] = @"session_tracking";
	event[EVENT_IS_ERROR] = @((bool)false);
	[Utils put:event key:@"adid" value:sessionSuccessResponseData.adid];
	[Utils put:event key:@"message" value:sessionSuccessResponseData.message];
	[Utils put:event key:@"timestamp" value:sessionSuccessResponseData.timestamp];
	[Utils dispatch_event:script_listener event:event];
}

-(void)adjustSessionTrackingFailed:(nullable ADJSessionFailure *)sessionFailureResponseData {
	NSMutableDictionary *event = [Utils new_event:ADJUST];
	event[EVENT_PHASE] = @"session_tracking";
	event[EVENT_IS_ERROR] = @((bool)true);
	[Utils put:event key:@"adid" value:sessionFailureResponseData.adid];
	[Utils put:event key:@"message" value:sessionFailureResponseData.message];
 [Utils put:event key:@"timestamp" value:sessionFailureResponseData.timestamp];
	[Utils put:event key:@"will_retry" value:@(sessionFailureResponseData.willRetry)];
	[Utils dispatch_event:script_listener event:event];
}

-(BOOL)adjustDeferredDeeplinkReceived:(nullable NSURL *)deeplink {
	NSMutableDictionary *event = [Utils new_event:ADJUST];
	event[EVENT_PHASE] = @"deeplink";
	event[EVENT_IS_ERROR] = @((bool)false);
	[Utils put:event key:@"url" value:deeplink.absoluteString];
	[Utils dispatch_event:script_listener event:event];
	return true;
}

@end

#pragma mark - Defold lifecycle -

void EXTENSION_INITIALIZE(lua_State *L) {
	extension_instance = [[ExtensionInterface alloc] init:L];
}

void EXTENSION_UPDATE(lua_State *L) {
	[Utils execute_tasks:L];
}

void EXTENSION_APP_ACTIVATE(lua_State *L) {
}

void EXTENSION_APP_DEACTIVATE(lua_State *L) {
}

void EXTENSION_FINALIZE(lua_State *L) {
    extension_instance = nil;
}

#endif
