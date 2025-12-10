
//red wire wrapped around front of robot
//front motors
int enA_front = 7; //blue
int motorinA1_front = 6;
int motorinA2_front = 5;
int motorinB1_front = 4;
int motorinB2_front = 3;
int enB_front = 2; //brown

//back motors
int enA_back = 13; //white
int motorinA1_back = 12; 
int motorinA2_back = 11;
int motorinB1_back = 10;
int motorinB2_back = 9;
int enB_back = 8; //yellow

// software PWM variables
unsigned long lastUpdate = 0;
int cycleTime = 20;    // milliseconds for full PWM cycle
int onTime = 0;        // how long motor is on in current cycle

// fake pwm
int targetSpeed = 0;   // 0–255, desired speed
char currentDirection = 'S';
int spd = 0;

void setup() {
  Serial.begin(115200);

  //initalize front
  pinMode(enA_front, OUTPUT);
  pinMode(motorinA1_front, OUTPUT);
  pinMode(motorinA2_front, OUTPUT);
  pinMode(enB_front, OUTPUT);
  pinMode(motorinB1_front, OUTPUT);
  pinMode(motorinB2_front, OUTPUT);

  //initalize back
  pinMode(enA_back, OUTPUT);
  pinMode(motorinA1_back, OUTPUT);
  pinMode(motorinA2_back, OUTPUT);
  pinMode(enB_back, OUTPUT);
  pinMode(motorinB1_back, OUTPUT);
  pinMode(motorinB2_back, OUTPUT);

}

//  speed (0–255)
void setSpeed(int speed){
  //set speed
  analogWrite(enA_front, speed);
  analogWrite(enB_front, speed);
  analogWrite(enA_back, speed);
  analogWrite(enB_back, speed); 
}

//  speed (0–255)
void forward(){
  //front wheels
  digitalWrite(motorinA1_front, LOW);
  digitalWrite(motorinA2_front, HIGH);
  digitalWrite(motorinB1_front, LOW);
  digitalWrite(motorinB2_front, HIGH);

  //back wheels 
  digitalWrite(motorinA1_back, HIGH);
  digitalWrite(motorinA2_back, LOW);
  digitalWrite(motorinB1_back, HIGH);
  digitalWrite(motorinB2_back, LOW);
  // Serial.println("Forwards");
}

//  speed (0–255)
void backward(){
  //front wheels
  digitalWrite(motorinA1_front, HIGH);
  digitalWrite(motorinA2_front, LOW);
  digitalWrite(motorinB1_front, HIGH);
  digitalWrite(motorinB2_front, LOW);

  //back wheels
  digitalWrite(motorinA1_back, LOW);
  digitalWrite(motorinA2_back, HIGH);
  digitalWrite(motorinB1_back, LOW);
  digitalWrite(motorinB2_back, HIGH);
}

// speed (0-255)
void turnLeft(){
  //front wheels
  digitalWrite(motorinA1_front, LOW);
  digitalWrite(motorinA2_front, HIGH);
  digitalWrite(motorinB1_front, HIGH);
  digitalWrite(motorinB2_front, LOW);

  //back wheels
  digitalWrite(motorinA1_back, LOW);
  digitalWrite(motorinA2_back, HIGH);
  digitalWrite(motorinB1_back, HIGH);
  digitalWrite(motorinB2_back, LOW);
}

void turnRight(){
  //front wheels
  digitalWrite(motorinA1_front, HIGH);
  digitalWrite(motorinA2_front, LOW);
  digitalWrite(motorinB1_front, LOW);
  digitalWrite(motorinB2_front, HIGH);

  //back wheels
  digitalWrite(motorinA1_back, HIGH);
  digitalWrite(motorinA2_back, LOW);
  digitalWrite(motorinB1_back, LOW);
  digitalWrite(motorinB2_back, HIGH);
}

void stopMotors() {
  digitalWrite(motorinA1_front, LOW);
  digitalWrite(motorinA2_front, LOW);
  digitalWrite(motorinB1_front, LOW);
  digitalWrite(motorinB2_front, LOW);
  digitalWrite(motorinA1_back, LOW);
  digitalWrite(motorinA2_back, LOW);
  digitalWrite(motorinB1_back, LOW);
  digitalWrite(motorinB2_back, LOW);
  analogWrite(enA_front, 0);
  analogWrite(enB_front, 0);
  analogWrite(enA_back, 0);
  analogWrite(enB_back, 0); 
  // Serial.println("Stopped");
}

// Map speed 0-100% to PWM duty cycle
int mapSpeedToDuty(int speedPercent) {
  int minDuty = 2;   // ~10% of cycleTime
  int maxDuty = cycleTime; // full cycle
  speedPercent = constrain(speedPercent, 0, 100);
  if (speedPercent == 0) return 0;
  if (speedPercent == 100) return maxDuty;
  return map(speedPercent, 0, 100, minDuty, maxDuty);
}


// Software PWM
void softwarePWM() {
  unsigned long now = millis();
  if (now - lastUpdate >= cycleTime) {
    lastUpdate = now;
    onTime = mapSpeedToDuty(targetSpeed);
  }

  unsigned long timeInCycle = millis() % cycleTime;
  if (timeInCycle < onTime) {
    // motor ON
    analogWrite(enA_front, 255);
    analogWrite(enB_front, 255);
    analogWrite(enA_back, 255);
    analogWrite(enB_back, 255);
  } else {
    // motor OFF
    analogWrite(enA_front, 0);
    analogWrite(enB_front, 0);
    analogWrite(enA_back, 0);
    analogWrite(enB_back, 0);
  }
}

unsigned long commandStart = 0;
unsigned long commandDuration = 800; // timeout in ms

void loop() {
  if (Serial.available() > 0) {
    //read command line
    char cmd = Serial.read();

    commandStart = millis();  // reset timeout timer

    switch (cmd) {
      case '\n':
        break;
      case 'F':
        currentDirection = 'F';
        forward();
        targetSpeed = 25;
        break;
      case 'B':
        currentDirection = 'B';
        backward();
        targetSpeed = 25;
        break;
      case 'L':
        currentDirection = 'L';
        turnLeft();
        targetSpeed = 20;
        break;
      case 'R':
        currentDirection = 'R';
        turnRight();
        targetSpeed = 20;
        break;
      case 'S':
        currentDirection = 'S';
        stopMotors();
        break;
      default:
        // Serial.print("Unknown command: ");
        // Serial.println(cmd);
        break;
    }
  }
  //reset count and stop motors
  // timeout check
  if (currentDirection != 'S' && millis() - commandStart > commandDuration) {
        stopMotors();
        currentDirection = 'S';
  }
  softwarePWM();
}
