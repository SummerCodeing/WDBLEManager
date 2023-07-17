//
//  XJKBLEPeripheral.h
//  
//
//  Created by summer on 2023/6/14.
//

#import <Foundation/Foundation.h>
#import <CoreBluetooth/CoreBluetooth.h>
@class CurPeripheral;

NS_ASSUME_NONNULL_BEGIN

@interface WDBLEPeripheral : NSObject
@property(nonatomic,copy) CBPeripheral *m_peripheral;
@property(nonatomic,copy) NSString *m_peripheralIdentifier;
@property(nonatomic,copy) NSString *m_peripheralLocaName;
@property(nonatomic,copy) NSString *m_peripheralName;
@property(nonatomic,copy) NSString *m_peripheralUUID;
@property(nonatomic,copy) NSNumber *m_peripheralRSSI;
@property(nonatomic,assign) BOOL    m_peripheralIsBind;
@property(nonatomic,assign)CFTimeInterval m_peripheralTime;  ///<当前时间
@property(nonatomic,copy) NSString *m_peripheralType;   ///<外设类型
@property(nonatomic,copy)NSDictionary *advertisementData;



@end

NS_ASSUME_NONNULL_END

NS_ASSUME_NONNULL_BEGIN
#pragma mark -- 单例类保存当前连接的外设 --

#define CURPERIPHERAL_INSTANCE [CurPeripheral shareInstance]
@interface CurPeripheral : NSObject

/// 当前连接的外设
@property (nonatomic,copy)CBPeripheral *currentPeripheral;

+ (instancetype)shareInstance;


@end
NS_ASSUME_NONNULL_END
