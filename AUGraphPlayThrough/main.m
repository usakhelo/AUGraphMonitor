//
//  main.m
//  AUGraphPlayThrough
//
//  Created by Sergo Pogosyan on 6/16/22.
//

#import <AudioToolbox/AudioToolbox.h>
#include "/Users/sergo/Downloads/CoreAudioUtilityClasses/CoreAudio/PublicUtility/CARingBuffer.h"

// #define PART_II

#pragma mark user-data struct
typedef struct MyAUGraphPlayer
{
    AudioStreamBasicDescription streamFormat;
    
    AUGraph graph;
    AudioUnit inputUnit;
    AudioUnit outputUnit;
#ifdef PART_II
    //8.23
#else
#endif
    
    AudioBufferList *inputBuffer;
    CARingBuffer *ringBuffer;
    
    Float64 firstInputSampleTime;
    Float64 firstOutputSampleTime;
    Float64 inToOutSampleTimeOffset;
} MyAUGraphPlayer;

#pragma mark - render procs -
OSStatus InputRenderProc(void *inRefCon,
                         AudioUnitRenderActionFlags *ioActionFlags,
                         const AudioTimeStamp *inTimeStamp,
                         UInt32 inBusNumber,
                         UInt32 inNumberFrames,
                         AudioBufferList *ioData)
{
    MyAUGraphPlayer *player = (MyAUGraphPlayer*)inRefCon;
    // Have we ever logged input timing? (for offset calculation)
    if (player->firstInputSampleTime < 0.0) {
        player->firstInputSampleTime = inTimeStamp->mSampleTime;
        if ((player->firstOutputSampleTime > 0.0) && (player->inToOutSampleTimeOffset < 0.0)) {
            player->inToOutSampleTimeOffset = player->firstInputSampleTime - player->firstOutputSampleTime;
        }
    }
    
    OSStatus inputProcErr = noErr;
    inputProcErr = AudioUnitRender(player->inputUnit,
                                   ioActionFlags,
                                   inTimeStamp,
                                   inBusNumber,
                                   inNumberFrames,
                                   player->inputBuffer);
    
    if (!inputProcErr) {
        inputProcErr = player->ringBuffer->Store(player->inputBuffer,
                                                 inNumberFrames,
                                                 inTimeStamp->mSampleTime);
    }
    return inputProcErr;
}
// 8.21 - 8.22
OSStatus GraphRenderProc(void *inRefCon,
                         AudioUnitRenderActionFlags *ioActionFlags,
                         const AudioTimeStamp *inTimeStamp,
                         UInt32 inBusNumber,
                         UInt32 inNumberFrames,
                         AudioBufferList *ioData)
{
    MyAUGraphPlayer *player = (MyAUGraphPlayer*)inRefCon;
    
    // Have we ever logged output timing? (for offset calculation)
    if (player->firstInputSampleTime < 0.0) {
        player->firstInputSampleTime = inTimeStamp->mSampleTime;
        if ((player->firstOutputSampleTime > 0.0) && (player->inToOutSampleTimeOffset < 0.0)) {
            player->inToOutSampleTimeOffset = player->firstInputSampleTime - player->firstOutputSampleTime;
        }
    }
    
    // Copy samples out of ring buffer
    OSStatus outputProcErr = noErr;
    outputProcErr = player->ringBuffer->Fetch(ioData,
                                              inNumberFrames,
                                              inTimeStamp->mSampleTime + player->inToOutSampleTimeOffset);
    return outputProcErr;
}

#pragma mark - utility functions
static void CheckError(OSStatus error, const char *operation)
{
    if (error == noErr) return;
    
    char errorString[20];
    // If 4-char-code
    *(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(error);
    if (isprint(errorString[1]) && isprint(errorString[2]) &&
        isprint(errorString[3]) && isprint(errorString[4])) {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    } else {
        sprintf(errorString, "%d", (int)error);
    }
    fprintf(stderr, "Error: %s (%s)\n", operation, errorString);
    
    exit(1);
}

// 8.4 - 8.14
void CreateInputUnit(MyAUGraphPlayer *player) {
    // Generate a description that matches audio HAL
    AudioComponentDescription inputcd = {0};
    inputcd.componentType = kAudioUnitType_Output;
    inputcd.componentSubType = kAudioUnitSubType_HALOutput;
    inputcd.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    AudioComponent comp = AudioComponentFindNext(NULL, &inputcd);
    if (comp == NULL) {
        printf("Can't get output unit");
        exit (-1);
    }
    
    UInt32 disableFlag = 0;
    UInt32 enableFlag = 1;
    AudioUnitElement outputBus = 0;
    AudioUnitElement inputBus = 1;
    
    CheckError(AudioComponentInstanceNew(comp, &player->inputUnit),
              "Couldn't open component for inputUnit");
    
    CheckError(AudioUnitSetProperty(player->inputUnit,
                                    kAudioOutputUnitProperty_EnableIO,
                                    kAudioUnitScope_Input,
                                    inputBus,
                                    &enableFlag,
                                    sizeof(enableFlag)),
               "Couldn't enable input on I/O unit");
    CheckError(AudioUnitSetProperty(player->inputUnit,
                                    kAudioOutputUnitProperty_EnableIO,
                                    kAudioUnitScope_Output,
                                    outputBus,
                                    &disableFlag,
                                    sizeof(disableFlag)),
               "Couldn't disable output on I/O unit");
    
    AudioDeviceID defaultDevice = kAudioObjectUnknown;
    UInt32 propertySize = sizeof(defaultDevice);
    AudioObjectPropertyAddress defaultDeviceProperty;
    defaultDeviceProperty.mSelector = kAudioHardwarePropertyDefaultInputDevice;
    defaultDeviceProperty.mScope = kAudioObjectPropertyScopeGlobal;
    defaultDeviceProperty.mElement = kAudioObjectPropertyElementMain;
    
    CheckError(AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                          &defaultDeviceProperty,
                                          0,
                                          NULL,
                                          &propertySize,
                                          &defaultDevice),
               "Couldn't get default input device");
    
    // A note from the book: Use kAudioHardwarePropertyDevices to iterate over all the devices
    
    CheckError(AudioUnitSetProperty(player->inputUnit,
                                    kAudioOutputUnitProperty_CurrentDevice,
                                    kAudioUnitScope_Global,
                                    outputBus,
                                    &defaultDevice,
                                    sizeof(defaultDevice)),
               "Couldn't set default device on I/O unit");
    
    propertySize = sizeof(AudioStreamBasicDescription);
    CheckError(AudioUnitGetProperty(player->inputUnit,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Output,
                                    inputBus,
                                    &player->streamFormat,
                                    &propertySize),
               "Couldn't get ASBD from input unit");
    AudioStreamBasicDescription deviceFormat;
    CheckError(AudioUnitGetProperty(player->inputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, inputBus, &deviceFormat, &propertySize), "Couldn't get ASBD from input unit");
    player->streamFormat.mSampleRate = deviceFormat.mSampleRate;
    
    propertySize = sizeof(AudioStreamBasicDescription);
    CheckError(AudioUnitSetProperty(player->inputUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, inputBus, &player->streamFormat, propertySize), "Couldn't set ASBD on input unit");
    UInt32 bufferSizeFrames = 0;
    propertySize = sizeof(UInt32);
    CheckError(AudioUnitGetProperty(player->inputUnit, kAudioDevicePropertyBufferFrameSize, kAudioUnitScope_Global, 0, &bufferSizeFrames, &propertySize), "Couldn't get buffer frame size from input unit");
    UInt32 bufferSizeBytes = bufferSizeFrames * sizeof(Float32);
    // Allocate an AudioBufferList plus enough space for
    // array of AudioBuffers
    
    UInt32 propsize = offsetof(AudioBufferList, mBuffers[0]) + (sizeof(AudioBuffer) * player->streamFormat.mChannelsPerFrame);
    // malloc buffer lists
    player->inputBuffer = (AudioBufferList *)malloc(propsize);
    player->inputBuffer->mNumberBuffers = player->streamFormat.mChannelsPerFrame;
    
    // Pre-malloc buffers for AudioBufferLists
    for (UInt32 i = 0, e = player->inputBuffer->mNumberBuffers; i < e; i++) {
        player->inputBuffer->mBuffers[i].mNumberChannels = 1;
        player->inputBuffer->mBuffers[i].mDataByteSize = bufferSizeBytes;
        player->inputBuffer->mBuffers[i].mData = malloc(bufferSizeBytes);
    }
    
    // Alloc ring buffer that will hold data between the
    // two audio devices
    player->ringBuffer = new CARingBuffer();
    player->ringBuffer->Allocate(player->streamFormat.mChannelsPerFrame, player->streamFormat.mBytesPerFrame, bufferSizeFrames * 3);
    
    // Set render proc to supply samples from input unit
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = InputRenderProc;
    callbackStruct.inputProcRefCon = player;
    
    CheckError(AudioUnitSetProperty(player->inputUnit, kAudioOutputUnitProperty_SetInputCallback,
                                    kAudioUnitScope_Global,
                                    0,
                                    &callbackStruct,
                                    sizeof(callbackStruct)),
               "Couldn't set input callback");
    
    CheckError(AudioUnitInitialize(player->inputUnit), "Couldn't initialize input unit");
    player->firstInputSampleTime = -1;
    player->inToOutSampleTimeOffset = -1;
    printf("Bottom of CreateInputUnit()\n");
}

void CreateMyAUGraph(MyAUGraphPlayer *player)
{
    // Create a new AUGraph
    CheckError(NewAUGraph(&player->graph),
               "NewAUGraph failed");
    
    // Generate a description that matches default output
    AudioComponentDescription outputcd = {0};
    outputcd.componentType = kAudioUnitType_Output;
    outputcd.componentSubType = kAudioUnitSubType_DefaultOutput;
    outputcd.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    AudioComponent comp = AudioComponentFindNext(NULL, &outputcd);
    if (comp == NULL) {
        printf ("Can't get output unit");
        exit(-1);
    }
    
    // Adds a node with above description to the graph
    AUNode outputNode;
    CheckError(AUGraphAddNode(player->graph,
                              &outputcd,
                              &outputNode),
               "AUGraphAddNode(DefaultOutput) failed");
#ifdef PART_II
    // 8.24 - 8.27
#else
    // Opening the graph opens all contained audio units
    // but does not allocate any resources yet
    CheckError(AUGraphOpen(player->graph),
               "AUGraphOpen failed");
    
    // Get the reference to the AudioUnit object for the
    // output graph node
    CheckError(AUGraphNodeInfo(player->graph,
                               outputNode,
                               NULL,
                               &player->outputUnit),
               "AUGraphNodeInfo failed");
    
    // Set the stream format on the output unit's input scope
    UInt32 propertySize = sizeof (AudioStreamBasicDescription);
    CheckError(AudioUnitSetProperty(player->outputUnit,
                                    kAudioUnitProperty_StreamFormat,
                                    kAudioUnitScope_Input,
                                    0,
                                    &player->streamFormat,
                                    propertySize),
               "Couldn't set stream format on output unit");
    
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = GraphRenderProc;
    callbackStruct.inputProcRefCon = player;
    
    CheckError(AudioUnitSetProperty(player->outputUnit,
                                    kAudioUnitProperty_SetRenderCallback,
                                    kAudioUnitScope_Global,
                                    0,
                                    &callbackStruct,
                                    sizeof(callbackStruct)),
               "Couldn't set render callback on output unit");
#endif
    
    // Now initialize the graph (causes resources to be allocated)
    CheckError(AUGraphInitialize(player->graph),
               "AUGraphInitialize failed");
    
    player->firstOutputSampleTime = -1;
}

// 8.29

// 8.2

int main(int argc, const char * argv[]) {
    
    MyAUGraphPlayer player = {0};
    
    // Create the input unit
    CreateInputUnit(&player);
    // Build a graph with output unit
    CreateMyAUGraph(&player);
    
#ifdef PART_II
    // 8.28
#else
#endif
    
    // Start playing
    CheckError(AudioOutputUnitStart(player.inputUnit), "AudioOuputUnitStart failed");
    CheckError(AUGraphStart(player.graph), "AUGraphStart");
    // And wait
    printf("Capturing, press <return> to stop:\n");
    getchar();
    
    // Cleanup
cleanup:
    AUGraphStop(player.graph);
    AUGraphUninitialize(player.graph);
    AUGraphClose(player.graph);
    
    @autoreleasepool {
        // insert code here...
        NSLog(@"Hello, World!");
    }
    return 0;
}

