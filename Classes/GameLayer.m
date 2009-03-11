/*
 * This file is part of Gorillas.
 *
 *  Gorillas is free software: you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation, either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  Gorillas is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with Gorillas in the file named 'COPYING'.
 *  If not, see <http://www.gnu.org/licenses/>.
 */

//
//  GameLayer.m
//  Gorillas
//
//  Created by Maarten Billemont on 19/10/08.
//  Copyright, lhunath (Maarten Billemont) 2008. All rights reserved.
//


#import "GameLayer.h"
#import "MainMenuLayer.h"
#import "GorillasAppDelegate.h"
#import "Remove.h"


@interface GameLayer (Private)

-(void) setPausedSilently:(BOOL)_paused;
-(void) shuffleGorillas;

@end

@implementation GameLayer


#pragma mark Properties

@synthesize paused;
@synthesize gorillas, activeGorilla;
@synthesize skiesLayer, panningLayer, buildingsLayer, windLayer, weather;

-(BOOL) singlePlayer {

    return humans == 1;
}


-(BOOL) isEnabled:(GorillasFeature)feature {
    
    // Make an exception for Score:
    if (feature == GorillasFeatureScore) {
        // Score is disabled if not single player AND not in team mode (non-team multiplayer), even if the feature is enabled.
        if (!self.singlePlayer && ![[GorillasAppDelegate get].gameLayer isEnabled:GorillasFeatureTeam])
            return NO;
    }
    
    return mode & feature;
}


-(void) setPaused:(BOOL)_paused {

    if(paused == _paused)
        // Nothing changed.
        return;
    
    [self setPausedSilently:_paused];
    
    if(running) {
        if(paused)
            [[GorillasAppDelegate get].uiLayer message:@"Paused"];
        else
            [[GorillasAppDelegate get].uiLayer message:@"Unpaused"];
    }
}


-(void) setPausedSilently:(BOOL)_paused {
    
    paused = _paused;
    
    [[UIApplication sharedApplication] setStatusBarHidden:!paused animated:YES];
    
    if(paused) {
        if(running)
            [self scaleTimeTo:0 duration:0.5f];
        [[GorillasAppDelegate get] hideHud];
        [windLayer runAction:[FadeTo actionWithDuration:[[GorillasConfig get] transitionDuration]
                                                opacity:0x00]];
    } else {
        [self scaleTimeTo:1 duration:1];
        [[GorillasAppDelegate get] popAllLayers];
        [[GorillasAppDelegate get] revealHud];
        [windLayer runAction:[FadeTo actionWithDuration:[[GorillasConfig get] transitionDuration]
                                                opacity:0xFF]];
    }
}


-(void) configureGameWithMode:(GorillasMode)_mode humans:(NSUInteger)_humans ais:(NSUInteger)_ais {
    
    mode = _mode;
    humans = _humans;
    ais = _ais;
}


#pragma mark Interact

-(void) reset {
    
    [skiesLayer reset];
    [panningLayer reset];
    [buildingsLayer reset];
    [windLayer reset];
    
    if ([[GorillasAppDelegate get].uiLayer rotation])
        [[GorillasAppDelegate get].uiLayer runAction:[RotateTo actionWithDuration:[[GorillasConfig get] transitionDuration]
                                                                            angle:0]];
}

-(void) shake {
    
    [AudioController vibrate];
    
    [buildingsLayer runAction:shakeAction];
}


-(void) startGame {

    if(running)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"Tried to start a game while one's still running."
                                     userInfo:nil];
    
    // Create gorillas array.
    if(activeGorilla)
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"Tried to start a game while there's still an active gorilla in the field."
                                     userInfo:nil];
    if(!gorillas)
        gorillas = [[NSMutableArray alloc] initWithCapacity:4];
    if([gorillas count])
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"Tried to start a game while there's still gorillas in the field."
                                     userInfo:nil];
    
    [GorillaLayer prepareCreation];
    
    // Add humans to the game.
    for (NSUInteger i = 0; i < humans; ++i) {
        NSString *name = @"Player";
        if(humans > 1)
            name = [NSString stringWithFormat:@"Player %d", i + 1];
        
        GorillaLayer *gorilla = [[GorillaLayer alloc] initWithName:name isHuman:YES];
        [gorillas addObject:gorilla];
        [gorilla release];
    }
    
    // Add AIs to the game.
    for (NSUInteger i = 0; i < ais; ++i) {
        NSString *name = @"Phone";
        if(ais > 1)
            name = [NSString stringWithFormat:@"Chip %d", i + 1];
        
        GorillaLayer *gorilla = [[GorillaLayer alloc] initWithName:name isHuman:NO];
        [gorillas addObject:gorilla];
        [gorilla release];
    }
    
    // Shuffle the order of the gorillas.
    [self shuffleGorillas];
    
    // When there are AIs in the game, show their difficulity.
    if (ais)
        [[GorillasAppDelegate get].uiLayer message:[[GorillasConfig get] levelName]];
    
    // Reset the game field and start the game.
    [buildingsLayer stopPanning];
    [self reset];
    [buildingsLayer startGame];
}


- (void)shuffleGorillas {
    
    NSUInteger count = [gorillas count];
    for (NSUInteger i = 0; i < count; ++i) {
        // Select a random element between i and end of array to swap with.
        int nElements = count - i;
        int n = (random() % nElements) + i;
        [gorillas exchangeObjectAtIndex:i withObjectAtIndex:n];
    }
}


-(void) updateStateHitGorilla:(BOOL)hitGorilla hitBuilding:(BOOL)hitBuilding offScreen:(BOOL)offScreen throwSkill:(float)throwSkill {

    if (offScreen)
        [[[GorillasAppDelegate get] hudLayer] message:[GorillasConfig get].offMessage
                                             duration:2 isImportant:NO];
    else if(hitGorilla && !buildingsLayer.hitGorilla.alive)
        [[[GorillasAppDelegate get] hudLayer] message:[NSString stringWithFormat:[GorillasConfig get].hitMessage,
                                                       activeGorilla.name, buildingsLayer.hitGorilla.name]
                                             duration:2 isImportant:NO];

    if (hitGorilla) {
        // Gorilla hit a gorilla.
        
        int score = 0;
        BOOL cheer = NO;
        if([activeGorilla human]) {
            // Human hits ...
            
            if([buildingsLayer.hitGorilla human]) {
                // ... Human.
                if([self isEnabled:GorillasFeatureTeam]
                   || buildingsLayer.hitGorilla == activeGorilla)
                    // In team mode or when suiciding, deduct score.
                    score = [[GorillasConfig get] deathScore];
                else
                    cheer = YES;
            }
            
            else {
                // ... AI.  Score boost.
                score = [[GorillasConfig get] killScore];
                cheer = YES;
            }
        } else {
            // AI hits ...
            
            if([buildingsLayer.hitGorilla human]) {
                // ... Human.
                if(![self isEnabled:GorillasFeatureTeam])
                    // In team mode, deduct score.
                    score = [[GorillasConfig get] deathScore];
                
                cheer = YES;
            } else {
                // ... AI.
                if(![self isEnabled:GorillasFeatureTeam]
                   && buildingsLayer.hitGorilla != activeGorilla)
                    // Not in team and not suiciding.
                    cheer = YES;
            }
        }
        
        // Update Skill.
        if([self isEnabled:GorillasFeatureSkill]) {
            float skill = 0;
            
            if([activeGorilla human]) {
                // Human skill.
                [[GorillasConfig get] setSkill:fminf(0.99f, [[GorillasConfig get] skill] / 2 + throwSkill)];
                skill = [GorillasConfig get].skill;
            } else
                // AI skill.
                skill = [GorillasConfig get].level;
            
            // Apply oneshot bonus.
            if(activeGorilla.turns == 0) {
                [[GorillasAppDelegate get].uiLayer message:@"Oneshot!"];
                skill *= [[GorillasConfig get] bonusOneShot];
            }
            
            if(score)
                score += (score / abs(score)) * [GorillasConfig get].bonusSkill * skill;
        }
        
        // Update Level.
        if([self isEnabled:GorillasFeatureLevel]) {
            score *= [[GorillasConfig get] level];
            
            NSString *oldLevel = [[GorillasConfig get] levelName];
            if(score > 0)
                [[GorillasConfig get] levelUp];
            else
                [[GorillasConfig get] levelDown];
            
            // Message in case we level up.
            if(![oldLevel isEqualToString:[[GorillasConfig get] levelName]]) {
                if(score > 0)
                    [[GorillasAppDelegate get].uiLayer message:@"Level Up!"];
                else
                    [[GorillasAppDelegate get].uiLayer message:@"Level Down"];
            }
        }
        
        // Update score.
        if([self isEnabled:GorillasFeatureScore] && score) {
            [GorillasConfig get].score += score;
            
            [[[GorillasAppDelegate get] hudLayer] updateHudWithScore:score skill:0];
            [buildingsLayer message:[NSString stringWithFormat:@"%+d", score] on:buildingsLayer.hitGorilla];
        }
        
        // If gorilla did something benefitial: cheer or dance.
        if(cheer) {
            if ([buildingsLayer.hitGorilla alive])
                [activeGorilla cheer];
            else
                [activeGorilla dance];
        }
        
        // Check whether any gorillas are left.
        int liveGorillaCount = 0;
        GorillaLayer *liveGorilla;
        for(GorillaLayer *_gorilla in gorillas)
            if([_gorilla alive]) {
                liveGorillaCount++;
                liveGorilla = _gorilla;
            }
        
        // If 0 or 1 gorillas left; show who won and stop the game.
        if(liveGorillaCount < 2) {
            if(liveGorillaCount == 1)
                [[[GorillasAppDelegate get] hudLayer] message:[NSString stringWithFormat:@"%@ wins!", [liveGorilla name]] duration:2 isImportant:NO];
            else
                [[[GorillasAppDelegate get] hudLayer] message:@"Tie!" duration:2 isImportant:NO];
        }
        
        // Reset the wind.
        [windLayer reset];
    }
    
    else if (hitBuilding || offScreen) {
        // Gorilla missed gorilla: either hit building or threw off screen.
        BOOL considderMiss = YES;
        
        if (!([[GorillasAppDelegate get].gameLayer isEnabled:GorillasFeatureScore]))
            // Don't deduct score when score not enabled.
            considderMiss = NO;
        
        if (!([[GorillasAppDelegate get].gameLayer.activeGorilla human]))
            // Don't deduct score for AI misses.
            considderMiss = NO;
        
        if (![[GorillasAppDelegate get].gameLayer isEnabled:GorillasFeatureTeam]) {
            NSUInteger humanGorillas = 0;
            for (GorillaLayer *gorilla in [GorillasAppDelegate get].gameLayer.gorillas)
                if ([gorilla human])
                    ++humanGorillas;
            
            if(humanGorillas != 1)
                // Don't deduct score for non-teamed multiplayer.
                considderMiss = NO;
        }
        
        if (considderMiss) {
            int score = [[GorillasConfig get] level] * [[GorillasConfig get] missScore];
            
            [GorillasConfig get].score += score;
            [[[GorillasAppDelegate get] hudLayer] updateHudWithScore:score skill:0];
            
            if(score)
                [buildingsLayer message:[NSString stringWithFormat:@"%+d", score] on:buildingsLayer.bananaLayer.banana];
        }
    }
}


-(BOOL) checkGameStillOn {

    if(running) {
        // Check to see if there are any opponents left.
        NSUInteger liveGorillas = 0;
        NSUInteger liveEnemyGorillas = 0;
        for (GorillaLayer *gorilla in gorillas) {
            if (![gorilla alive])
                continue;
            
            // Gorilla is alive.
            ++liveGorillas;
            
            // Gorilla is on active gorilla's team.
            if (gorilla.human != activeGorilla.human)
                ++liveEnemyGorillas;
        }
        
        if(liveGorillas < 2)
            running = NO;
        
        if([self isEnabled:GorillasFeatureTeam]
           && !liveEnemyGorillas)
            running = NO;
    }
    
    return running;
}


-(void) stopGame {
    
    mode = 0;
    humans = 0;
    ais = 0;
    
    [self endGame];
}


-(void) endGame {
    
    [self setPausedSilently:NO];

    // FIXME: Hack to avoid issue with stopGame removing parent from throw smoke (bananaLayer)
    // This causes the smoke's step: that occurs later in the event processing queue that
    // triggered this call to reference a dealloced parent (bananaLayer).
    [self schedule:@selector(endGameFix:)];
}


-(void) endGameFix:(ccTime)dt {
    
    [self unschedule:@selector(endGameFix:)];
    [buildingsLayer stopGame];
}


#pragma mark Internal

-(id) init {
    
	if (!(self = [super init]))
		return self;

    running = NO;
    
    IntervalAction *l = [MoveBy actionWithDuration:.05f position:cpv(-3, 0)];
    IntervalAction *r = [MoveBy actionWithDuration:.05f position:cpv(6, 0)];
    shakeAction = [[Sequence actions:l, r, l, l, r, l, nil] retain];
    
    // Set up our own layer.
    CGSize winSize = [[Director sharedDirector] winSize];
    [self setTransformAnchor:cpv(winSize.width / 2, winSize.height / 2)];
    
    // Sky, buildings and wind.
    buildingsLayer = [[BuildingsLayer alloc] init];
    [buildingsLayer setTransformAnchor:cpvzero];

    skiesLayer = [[SkiesLayer alloc] init];
    [skiesLayer setTransformAnchor:cpvzero];
    
    panningLayer = [[PanningLayer alloc] init];
    [panningLayer setTransformAnchor:cpvzero];
    [panningLayer addChild:buildingsLayer z:0];
    [panningLayer addChild:skiesLayer z:-5 parallaxRatio:cpv(0.3f, 0.8f)];
    [self addChild:panningLayer];
    
    windLayer = [[WindLayer alloc] init];
    [windLayer setColor:0xffffff00];
    [self addChild:windLayer z:5];

    // Make sure we're paused, hide HUD and show status bar.
    [self setPausedSilently:YES];

    return self;
}


-(void) onEnter {
    
    [super onEnter];
    
    if ([[GorillasConfig get] weather])
        [self schedule:@selector(updateWeather:) interval:1];
}


-(void) onExit {

    [super onExit];
    
    [self unschedule:@selector(updateWeather:)];
}


-(void) updateWeather:(ccTime)dt {
    
    if (![[GorillasConfig get] weather] && [weather active])
        [weather stopSystem];
    
    if (![weather emissionRate]) {
        // If not emitting ..
        
        if ([weather active])
            // Stop active system.
            [weather stopSystem];
        
        if ([weather particleCount] == 0) {
            // If system has no particles left alive ..
            
            // Remove & release it.
            [windLayer unregisterSystem:weather];
            [[weather parent] removeChild:weather cleanup:YES];
            [weather release];
            weather = nil;
            
            if ([[GorillasConfig get] weather] && random() % 10 == 0) {
                // 10% chance to start snow/rain when weather is enabled.
            
                switch (random() % 2) {
                    case 0:
                        weather = [[ParticleRain alloc] init];
                        [weather setEmissionRate:60];
                        [weather setSizeVar:1.5f];
                        [weather setSize:3];
                        break;
                    
                    case 1:
                        weather = [[ParticleSnow alloc] init];
                        [weather setSpeed:10];
                        [weather setEmissionRate:3];
                        [weather setSizeVar:3];
                        [weather setSize:4];
                        break;
                }
                
                [weather setPosVar:cpv([weather posVar].x * 2.5f, [weather posVar].y)];
                [weather setPosition:cpv([weather position].x, [weather position].y * 2)]; // Space above screen.
                [buildingsLayer addChild:weather z:-3 parallaxRatio:cpv(1.3f, 1.8f)];

                [windLayer registerSystem:weather affectAngle:YES];
            }
        }
    }
    
    else {
        // System is alive, let the emission rate evolve.
        float rate = [weather emissionRate] + (random() % 40 - 15) / 10.0f;
        float max = [weather isKindOfClass:[ParticleRain class]]? 100: 50;
        rate = fminf(fmaxf(0, rate), max);

        if(random() % 100 == 0)
            // 1% chance for a full stop.
            rate = 0;
    
        [weather setEmissionRate:rate];
    }
}


-(void) started {
    
    running = YES;

    [self setPausedSilently:NO];
}


-(void) stopped {
    
    running = NO;
    
    [activeGorilla release];
    activeGorilla = nil;
    
    if([self rotation])
        [self runAction:[RotateTo actionWithDuration:[[GorillasConfig get] transitionDuration]
                                               angle:0]];
    if([panningLayer position].x != 0 || [panningLayer position].y != 0)
        [panningLayer runAction:[MoveTo actionWithDuration:[[GorillasConfig get] transitionDuration]
                                                  position:cpvzero]];
    
    if(mode)
        [[GorillasAppDelegate get] showContinueMenu];
    else
        // Selected game mode was unset, can't "continue".
        [[GorillasAppDelegate get] showMainMenu];
}


-(void) dealloc {
    
    [shakeAction release];
    shakeAction = nil;
    
    [skiesLayer release];
    skiesLayer = nil;
    
    [buildingsLayer release];
    buildingsLayer = nil;
    
    [weather release];
    weather = nil;
    
    [panningLayer release];
    panningLayer = nil;
    
    [windLayer release];
    windLayer = nil;
    
    [gorillas release];
    gorillas = nil;
    
    [activeGorilla release];
    activeGorilla = nil;
    
    [super dealloc];
}


@end
