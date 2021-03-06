/*
  OpenMW - The completely unofficial reimplementation of Morrowind
  Copyright (C) 2008  Nicolay Korslund
  Email: < korslund@gmail.com >
  WWW: http://openmw.snaptoad.com/

  This file (events.d) is part of the OpenMW package.

  OpenMW is distributed as free software: you can redistribute it
  and/or modify it under the terms of the GNU General Public License
  version 3, as published by the Free Software Foundation.

  This program is distributed in the hope that it will be useful, but
  WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  General Public License for more details.

  You should have received a copy of the GNU General Public License
  version 3 along with this program. If not, see
  http://www.gnu.org/licenses/ .

 */

module input.events;

import std.stdio;
import std.string;

import sound.audio;

import core.config;

import scene.soundlist;
import scene.player;

import bullet.bindings;

import monster.monster;
import monster.vm.dbg;

import ogre.bindings;
import gui.bindings;
import gui.gui;

import input.keys;
import input.ois;

// Debug output
//debug=printMouse;      // Mouse button events
//debug=printMouseMove;  // Mouse movement events
//debug=printKeys;       // Keypress events

// TODO: Jukebox controls and other state-related data will later be
// handled entirely in script code, as will some of the key bindings.

// Pause?
bool pause = false;
int *guiMode;

const float volDiff = 0.05;

void musVolume(bool increase)
{
  float diff = -volDiff;
  if(increase) diff = -diff;
  config.setMusicVolume(diff + config.getMusicVolume);
  writefln(increase?"Increasing":"Decreasing", " music volume to ", config.getMusicVolume);
}

void sfxVolume(bool increase)
{
  float diff = -volDiff;
  if(increase) diff = -diff;
  config.setSfxVolume(diff + config.getSfxVolume);
  writefln(increase?"Increasing":"Decreasing", " sound effect volume to ", config.getSfxVolume);
}

void mainVolume(bool increase)
{
  float diff = -volDiff;
  if(increase) diff = -diff;
  config.setMainVolume(diff + config.getMainVolume);
  writefln(increase?"Increasing":"Decreasing", " main volume to ", config.getMainVolume);
}

void updateMouseSensitivity()
{
  effMX = *config.mouseSensX;
  effMY = *config.mouseSensY;
  if(*config.flipMouseY) effMY = -effMY;
}

void togglePause()
{
  pause = !pause;
  if(pause) writefln("Pause");
  else writefln("Pause off");
}

extern(C) void d_handleMouseButton(MouseState *state, int button)
{
  debug(printMouse)
    writefln("handleMouseButton %s: Abs(%s, %s, %s)", button, 
             state.X.abs, state.Y.abs, state.Z.abs);

  // For the moment, just treat mouse clicks as normal key presses.
  d_handleKey(cast(KC) (KC.Mouse0 + button));
}

// Handle a keyboard event through key bindings. Direct movement
// (eg. arrow keys) is not handled here, see d_frameStarted() below.
extern(C) void d_handleKey(KC keycode, dchar text = 0)
{
  // Do some preprocessing on the data to account for OIS
  // shortcommings.

  // Some keys (especially international keys) have no key code but
  // return a character instead.
  if(keycode == 0)
    {
      // If no character is given, just drop this event since OIS did
      // not manage to give us any useful data at all.
      if(text == 0) return;

      keycode = KC.CharOnly;
    }

  // Debug output
  debug(printKeys)
    {
      char[] str;
      if(keycode >= 0 && keycode < keysymToString.length)
        str = keysymToString[keycode];
      else str = "OUT_OF_RANGE";
      writefln("Key %s, text '%s', name '%s'", keycode, text, str);
    }

  // Look up the key binding. We have to send both the keycode and the
  // text.
  Keys k = keyBindings.findMatch(keycode, text);

  // These are handled even if we are in gui mode:
  if(k)
    switch(k)
      {
      case Keys.ToggleGui: gui_toggleGui(); return;
      case Keys.Console: gui_toggleConsole(); return;
      case Keys.ScreenShot: takeScreenShot(); return;
      default:
      }

  if(*guiMode) return;

  if(k)
    switch(k)
      {
      case Keys.ToggleBattleMusic:
        Music.toggle();
        return;

      case Keys.MainVolUp: mainVolume(true); return;
      case Keys.MainVolDown: mainVolume(false); return;
      case Keys.MusVolUp: musVolume(true); return;
      case Keys.MusVolDown: musVolume(false); return;
      case Keys.SfxVolUp: sfxVolume(true); return;
      case Keys.SfxVolDown: sfxVolume(false); return;
      case Keys.Mute: Music.toggleMute(); return;
      case Keys.Fullscreen: toggleFullscreen(); return;

      case Keys.PhysMode: bullet_nextMode(); return;
      case Keys.Nighteye: ogre_toggleLight(); return;

      case Keys.Debug: return;
      case Keys.Pause: togglePause(); return;
      case Keys.Exit: exitProgram(); return;
      default:
        assert(k >= 0 && k < keyToString.length);
        writefln("WARNING: Event %s has no effect", keyToString[k]);
      }
  return;
}

// Refresh rate for sfx placements, in seconds.
const float sndRefresh = 0.17;

// Refresh rate for music fadeing, seconds.
const float musRefresh = 0.05;

// Walking / floating speed, in points per second.
float speed = 300;

float sndCumTime = 0;
float musCumTime = 0;

// Move the player according to playerData.position
void movePlayer()
{
  // Move the player into place. TODO: This isn't really input-related
  // at all, and should be moved.
  with(*playerData.position)
    {
      ogre_moveCamera(position[0], position[1], position[2]);
      ogre_setCameraRotation(rotation[0], rotation[1], rotation[2]);

      bullet_movePlayer(position[0], position[1], position[2]);
    }
}

void initializeInput()
{
  movePlayer();

  // TODO/FIXME: This should have been in config, but DMD's module
  // system is on the brink of collapsing, and it won't compile if I
  // put another import in core.config. I should probably check the
  // bug list and report it.
  updateMouseSensitivity();

  // Get a pointer to the 'guiMode' flag in cpp_ogre.cpp
  guiMode = gui_getGuiModePtr();
}

extern(C) int ois_isPressed(int keysym);

// Check if a key is currently down
bool isPressed(Keys key)
{
  KeyBind *b = &keyBindings.bindings[key];
  foreach(i; b.syms)
    if(i != 0 && ois_isPressed(i)) return true;
  return false;
}

// Enable superman mode, ie. flight and super-speed. Only used for
// debugging the terrain mode.
extern(C) void d_terr_superman()
{
  bullet_fly();
  speed = 8000;

  with(*playerData.position)
    {
      position[0] = 20000;
      position[1] = -70000;
      position[2] = 30000;
    }
  movePlayer();
}

extern(C) int d_frameStarted(float time)
{
  if(doExit) return 0;

  dbg.trace("d_frameStarted");
  scope(exit) dbg.untrace();

  // Run the Monster scheduler
  vm.frame(time);

  musCumTime += time;
  if(musCumTime > musRefresh)
    {
      Music.updateBuffers();
      musCumTime -= musRefresh;
    }

  // The rest is ignored in pause or GUI mode
  if(pause || *guiMode > 0) return 1;

  // Check if the movement keys are pressed
  float moveX = 0, moveY = 0, moveZ = 0;
  float x, y, z, ox, oy, oz;

  if(isPressed(Keys.MoveLeft)) moveX -= speed;
  if(isPressed(Keys.MoveRight)) moveX += speed;
  if(isPressed(Keys.MoveForward)) moveZ -= speed;
  if(isPressed(Keys.MoveBackward)) moveZ += speed;

  // TODO: These should be enabled for floating modes (like swimming
  // and levitation) and disabled for everything else.
  if(isPressed(Keys.MoveUp)) moveY += speed;
  if(isPressed(Keys.MoveDown)) moveY -= speed;

  // This isn't very elegant, but it's simple and it works.

  // Get the current coordinates
  ogre_getCameraPos(&ox, &oy, &oz);

  // Move camera using relative coordinates. TODO: We won't really
  // need to move the camera here (since it's moved below anyway), we
  // only want the transformation from camera space to world
  // space. This can likely be done more efficiently.
  ogre_moveCameraRel(moveX, moveY, moveZ);

  // Get the result
  ogre_getCameraPos(&x, &y, &z);

  // The result is the real movement direction, in world coordinates
  moveX = x-ox;
  moveY = y-oy;
  moveZ = z-oz;

  // Tell Bullet that this is where we want to go
  bullet_setPlayerDir(moveX, moveY, moveZ);

  // Perform a Bullet time step
  bullet_timeStep(time);

  // Get the final (actual) player position and update the camera
  bullet_getPlayerPos(&x, &y, &z);
  ogre_moveCamera(x,y,z);

  // Store it in the player object
  playerData.position.position[0] = x;
  playerData.position.position[1] = y;
  playerData.position.position[2] = z;

  if(!config.noSound)
    {
      // Tell the sound scene that the player has moved
      sndCumTime += time;
      if(sndCumTime > sndRefresh)
        {
          float fx, fy, fz;
          float ux, uy, uz;

          ogre_getCameraOrientation(&fx, &fy, &fz, &ux, &uy, &uz);

          soundScene.update(x,y,z,fx,fy,fz,ux,uy,uz);
          sndCumTime -= sndRefresh;
        }
    }
  return 1;
}

bool collides = false;
