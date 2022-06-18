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
// 8.3
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
    Float64 inToOutSampleTimeOffer;
} MyAUGraphPlayer;

#pragma mark - render procs -
// 8.15 - 8.18
// 8.21 - 8.22

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
    
}

// 8.19 - 8.20
void CreateMyAUGraph(MyAUGraphPlayer *player)
{
#ifdef PART_II
    // 8.24 - 8.27
#else
#endif
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

