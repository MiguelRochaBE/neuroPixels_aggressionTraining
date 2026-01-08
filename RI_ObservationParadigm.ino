#include <Conceptinetics.h>
#include <AccelStepper.h>

// Timing constants (mins)
unsigned const long secs = 60;
unsigned const long ms =   1000;

unsigned const long BASELINE_RED_START_TIME         = 0;
unsigned const long BASELINE_RED_BRIGHT_TIME        = (long) (5 * ms);
unsigned const long SOLENOID1                       = (long) (45 * ms);
unsigned const long STOP1                           = (long) (SOLENOID1 + (75 * ms));
unsigned const long OLF1                            = (long) (STOP1 + (30 * ms));
unsigned const long STOP2                           = (long) (OLF1 + 105 * ms);
unsigned const long ANTECIPATION_WHITE_START_TIME   = (long) (STOP2 + 30 * ms);
unsigned const long ANTECIPATION_WHITE_BRIGHT_TIME  = (long) (ANTECIPATION_WHITE_START_TIME + 5 * ms);
unsigned const long MOTOR_ENABLE_TIME               = (long) (ANTECIPATION_WHITE_START_TIME + 60 * ms);
unsigned const long MOTOR_DISABLE_TIME              = (long) (MOTOR_ENABLE_TIME + 5 * ms);
unsigned const long POST_AGGRESSION_RED_START_TIME  = (long) (MOTOR_ENABLE_TIME + 5 * secs * ms);
unsigned const long POST_AGGRESSION_RED_BRIGHT_TIME = (long) (POST_AGGRESSION_RED_START_TIME + 5 * ms);
unsigned const long OLF2                            = (long) (POST_AGGRESSION_RED_START_TIME + 5 * secs * ms);
unsigned const long STOP3                           = (long) (OLF2 + 105 * ms);
unsigned const long SOLENOID2                       = (long) (STOP3 + 30 * ms);
unsigned const long STOP4                           = (long) (SOLENOID2 + 75 * ms);
unsigned const long END_PARADIGM                    = (long) (STOP4 + 45 * ms);
unsigned const long RESTART_PARADIGM                = (long) (END_PARADIGM + 240 * ms);

// Trigger pin to start the sequence
#define TRIGGER_PIN 3

// Solenoid
#define SOLENOID_PIN 40
unsigned const long milk_N = 6;
const unsigned long milk_ITI = 15 * ms;
unsigned long milk_iteration = 0;
bool deliveryDone = false;

// uArm 
unsigned const long olf_N = 8;
unsigned const long olf_ITI = 15 * ms;
bool move1 = true;
bool move2 = false;
unsigned long olf_iteration = 0;

// Motor driver
#define DIR_PIN 9
#define STEP_PIN 10
#define RESET_PIN 11
#define ENABLE_PIN 12
#define GATE_TTL_PIN 44 

#define STEPS_PER_REVOLUTION 200 
#define MICROSTEP_MODE 16

AccelStepper gate(AccelStepper::DRIVER, STEP_PIN, DIR_PIN);
bool motorStarted = false;

// DMX LED driver
#define RED_CHANNEL 1
#define GREEN_CHANNEL 2
#define BLUE_CHANNEL 3
#define WHITE_CHANNEL 4

#define DMX_CHANNELS 4
#define DMX_DE_RE_PIN 4  // Pin connected to DE/RE on RS485 driver
#define LIGHT_TTL_PIN 42 

#define MAX_LIGHT_INTENSITY 255
DMX_Master dmxMaster(DMX_CHANNELS, DMX_DE_RE_PIN);

enum State {WAITING_FOR_TRIGGER, 
            BASELINE_RED_FADE_IN, 
            MILK_DELIVERY1,
            OLFACTORY_STIM1,
            ANTECIPATION_WHITE_FADE_IN, 
            FIGHT_MOVE_GATE, 
            POST_AGGRESSION_RED_RETURN,
            OLFACTORY_STIM2, 
            MILK_DELIVERY2,
            END};

State currentState = WAITING_FOR_TRIGGER;

unsigned long triggerTime = 0;

void setup() {
  Serial.begin(115200);  // USB connection (Debugging)
  Serial2.begin(115200); // uArm
  
  pinMode(TRIGGER_PIN, INPUT);

  //Solenoid valve
  pinMode(SOLENOID_PIN, OUTPUT);
  digitalWrite(SOLENOID_PIN, HIGH);

  // Motor setup
  pinMode(RESET_PIN, OUTPUT);
  pinMode(ENABLE_PIN, OUTPUT);
  pinMode(GATE_TTL_PIN, OUTPUT);
  digitalWrite(RESET_PIN, LOW);
  digitalWrite(ENABLE_PIN, HIGH);
  digitalWrite(GATE_TTL_PIN, LOW);

  gate.setMaxSpeed(200 * MICROSTEP_MODE);
  gate.setAcceleration(20 * MICROSTEP_MODE);
  gate.moveTo((int)(STEPS_PER_REVOLUTION/4 * MICROSTEP_MODE) + 10); // 1/4 of a revolution

  // DMX setup
  pinMode(LIGHT_TTL_PIN, OUTPUT);
  digitalWrite(LIGHT_TTL_PIN, LOW);
  dmxMaster.enable();
  dmxMaster.setChannelRange(1, 4, 0); // All lights off initially

  Serial2.println("M2232 V1"); // Close the gipper on the uArm

  Serial.println("======== Resident Intruder observation paradigm ========");
}

void loop() {
  unsigned long time = millis();

  switch (currentState) 
  {
    case WAITING_FOR_TRIGGER:
      if (digitalRead(TRIGGER_PIN) == HIGH && triggerTime == 0) 
      {
        triggerTime = time;
        currentState = BASELINE_RED_FADE_IN;
        Serial.println("Trigger detected. Starting paradigm...");
      }
      break;

    case BASELINE_RED_FADE_IN:
      if (time - triggerTime >= BASELINE_RED_START_TIME && time - triggerTime < BASELINE_RED_BRIGHT_TIME) 
      {
        static bool printed = false;
        if (!printed) 
        {
          Serial.print("Recording aggression baseline for ");
          Serial.print((int)(((SOLENOID1 - BASELINE_RED_START_TIME)/ms)));
          Serial.print(" seconds. (RED LIGHT) \n");
          printed = true;

          digitalWrite(LIGHT_TTL_PIN, HIGH);

          Serial2.println("G0 X45 Y-90 Z20 F15"); // Homing the robot's position
        }

        int redLevel = map(time - triggerTime, 
                           BASELINE_RED_START_TIME, 
                           BASELINE_RED_BRIGHT_TIME-1, 
                           0, 
                           MAX_LIGHT_INTENSITY);

        dmxMaster.setChannelValue(RED_CHANNEL, redLevel);
        dmxMaster.setChannelValue(GREEN_CHANNEL, 0);
        dmxMaster.setChannelValue(BLUE_CHANNEL, 0);
        dmxMaster.setChannelValue(WHITE_CHANNEL, 0);
      }
      else if(time - triggerTime >= BASELINE_RED_BRIGHT_TIME)
      {
        currentState = MILK_DELIVERY1;
      }     
      break;

    case MILK_DELIVERY1:
      if (milk_iteration < milk_N)
      {
        unsigned long deliveryStart = SOLENOID1 + milk_ITI * milk_iteration;
        unsigned long deliveryEnd = deliveryStart + 50;
        if (!deliveryDone && (time - triggerTime) >= deliveryStart && time - triggerTime < deliveryEnd) 
        {
          Serial.print("(1) Milk stimuli delivery n: ");
          Serial.println(milk_iteration + 1);
          digitalWrite(SOLENOID_PIN, LOW); // Activate solenoid
          deliveryDone = true;
        } 
        else if (deliveryDone && time - triggerTime >= deliveryEnd && time - triggerTime <= SOLENOID1 + milk_ITI * (milk_iteration + 1)) 
        {
          digitalWrite(SOLENOID_PIN, HIGH); // Deactivate solenoid
          milk_iteration++;
          deliveryDone = false;
        } 
      }
      else
      {
        Serial.println("=== 30s pause ===");
        milk_iteration = 0;
        currentState = OLFACTORY_STIM1;
      }

      break;

    case OLFACTORY_STIM1:
      if(olf_iteration < olf_N)
      {
        unsigned long deliveryStart = OLF1 + olf_ITI * olf_iteration;
        unsigned long deliveryEnd = deliveryStart + 7 * ms; 
        if(move1 && time - triggerTime >= deliveryStart && time - triggerTime < deliveryEnd)
        {
          Serial.print("(1) Olfactory stimuli delivery n: ");
          Serial.print(olf_iteration + 1);
          Serial.println(" ");

          Serial2.println("G0 X180 Y-250 Z30 F15");

          move1 = false;
          move2 = true;

        }
        else if(move2 && time - triggerTime >= deliveryEnd && OLF1 + olf_ITI * (olf_iteration + 1))
        {
          Serial2.println("G0 X45 Y-90 Z20 F15");

          move1 = true;
          move2 = false; 

          olf_iteration++;
        }
      }
      else
      {
        Serial.println("=== 30s pause ===");
        olf_iteration = 0;
        currentState = ANTECIPATION_WHITE_FADE_IN;
      }
      break;

    case ANTECIPATION_WHITE_FADE_IN:
      if (time - triggerTime >=  ANTECIPATION_WHITE_START_TIME && time - triggerTime < ANTECIPATION_WHITE_BRIGHT_TIME) 
      {
        static bool printed = false;
        if (!printed) 
        {
            Serial.print("Recording aggression anticipation for ");
            Serial.print((long)(((MOTOR_ENABLE_TIME - ANTECIPATION_WHITE_START_TIME)/ms)/secs));
            Serial.print(" min. (WHITE LIGHT)\n");
            printed = true;

            digitalWrite(LIGHT_TTL_PIN, LOW);
        }

        int whiteLevel = map(time - triggerTime, 
                             ANTECIPATION_WHITE_START_TIME, 
                             ANTECIPATION_WHITE_BRIGHT_TIME-1, 
                             0, 
                             MAX_LIGHT_INTENSITY - 204);

        dmxMaster.setChannelValue(RED_CHANNEL, MAX_LIGHT_INTENSITY - (int)(whiteLevel*4));
        dmxMaster.setChannelValue(GREEN_CHANNEL, whiteLevel);
        dmxMaster.setChannelValue(BLUE_CHANNEL, whiteLevel);
        dmxMaster.setChannelValue(WHITE_CHANNEL, whiteLevel);
      } 
      else if (time - triggerTime >= ANTECIPATION_WHITE_BRIGHT_TIME) 
      {
        currentState = FIGHT_MOVE_GATE;
      } 
      break;

    case FIGHT_MOVE_GATE:
      if (!motorStarted && time - triggerTime >= MOTOR_ENABLE_TIME) 
      {
        Serial.print("Activating the gate's motor - Arena mice fighting for ");
        Serial.print((long)((POST_AGGRESSION_RED_START_TIME - MOTOR_ENABLE_TIME)/ms)/secs);
        Serial.println(" min. (WHITE LIGHT)");

        digitalWrite(RESET_PIN, HIGH);
        digitalWrite(ENABLE_PIN, LOW);
        motorStarted = true;
        
        digitalWrite(GATE_TTL_PIN, HIGH);
      }

      if (motorStarted) {
        gate.run(); // Run the motor every loop
        if (!gate.isRunning() && time - triggerTime >= MOTOR_DISABLE_TIME) 
        {
          digitalWrite(ENABLE_PIN, HIGH);
          digitalWrite(RESET_PIN, LOW);
          Serial.println("Motor movement complete.");
          currentState = POST_AGGRESSION_RED_RETURN;
        }
      }
      break;

    case POST_AGGRESSION_RED_RETURN:
      if (time - triggerTime >= POST_AGGRESSION_RED_START_TIME && time - triggerTime < POST_AGGRESSION_RED_BRIGHT_TIME) 
      {
        static bool printed = false;
        if (!printed) 
        {
            Serial.print("Recording post aggression baseline for ");
            Serial.print((long)(((OLF2 - POST_AGGRESSION_RED_START_TIME) / ms)/secs));
            Serial.print(" min. (RED LIGHT)\n");
            printed = true;

            digitalWrite(LIGHT_TTL_PIN, HIGH);
        }
        int lvl = MAX_LIGHT_INTENSITY - 204;
        int redLevel = map(time - triggerTime, 
                           POST_AGGRESSION_RED_START_TIME, 
                           POST_AGGRESSION_RED_BRIGHT_TIME - 1, 
                           0, 
                           MAX_LIGHT_INTENSITY - lvl);

        dmxMaster.setChannelValue(RED_CHANNEL, lvl + redLevel);
        dmxMaster.setChannelValue(GREEN_CHANNEL, lvl - (int)(redLevel/4));
        dmxMaster.setChannelValue(BLUE_CHANNEL, lvl - (int)(redLevel/4));
        dmxMaster.setChannelValue(WHITE_CHANNEL, lvl - (int)(redLevel/4));
      }
      else if(time - triggerTime >= POST_AGGRESSION_RED_BRIGHT_TIME)
      {
        currentState = OLFACTORY_STIM2;
      }
      break;

    case OLFACTORY_STIM2:
      if(olf_iteration < olf_N)
      {
        unsigned long deliveryStart = OLF2 + olf_ITI * olf_iteration;
        unsigned long deliveryEnd = deliveryStart + 7 * ms; 
        if(move1 && time - triggerTime >= deliveryStart && time - triggerTime < deliveryEnd)
        {
          Serial.print("(2) Olfactory stimuli delivery n: ");
          Serial.print(olf_iteration + 1);
          Serial.println(" ");

          Serial2.println("G0 X180 Y-250 Z30 F15");

          move1 = false;
          move2 = true;

        }
        else if(move2 && time - triggerTime >= deliveryEnd && OLF2 + olf_ITI * (olf_iteration + 1))
        {
          Serial2.println("G0 X45 Y-90 Z20 F15");

          move1 = true;
          move2 = false; 

          olf_iteration++;
        }
      }
      else
      {
        Serial.println("=== 30s pause ===");
        currentState = MILK_DELIVERY2;
      }
      break;

    case MILK_DELIVERY2:
      if (milk_iteration < milk_N)
      {
        unsigned long deliveryStart = SOLENOID2 + milk_ITI * milk_iteration;
        unsigned long deliveryEnd = deliveryStart + 50;
        if (!deliveryDone && (time - triggerTime) >= deliveryStart && time - triggerTime < deliveryEnd) 
        {
          Serial.print("(2) Milk stimuli delivery n: ");
          Serial.println(milk_iteration + 1);
          digitalWrite(SOLENOID_PIN, LOW); // Activate solenoid
          deliveryDone = true;
        } 
        else if (deliveryDone && time - triggerTime >= deliveryEnd && time - triggerTime <= SOLENOID2 + milk_ITI * (milk_iteration + 1)) 
        {
          digitalWrite(SOLENOID_PIN, HIGH); // Deactivate solenoid
          milk_iteration++;
          deliveryDone = false;
        } 
      }
      else
      {
        Serial.println("=== 45s to end paradigm ===");
        currentState = END;
      }
      break;

    case END:
      if (time - triggerTime >= END_PARADIGM)
      {
        static bool printed = false;
        if (!printed) 
        {
          Serial.println("Ending paradigm.");
          printed = true;

          digitalWrite(LIGHT_TTL_PIN, LOW);
          digitalWrite(GATE_TTL_PIN, LOW);
        }

        dmxMaster.setChannelValue(RED_CHANNEL, 0); 
        dmxMaster.setChannelValue(GREEN_CHANNEL, 0);
        dmxMaster.setChannelValue(BLUE_CHANNEL, 0);
        dmxMaster.setChannelValue(WHITE_CHANNEL, 0);
      }
      break;
  }
}
