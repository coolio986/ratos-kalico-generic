# Servo Enable Delay for Klipper
# Inserts a dwell before homing moves for configured servo axes
# so step servos have time to initialise before steps are sent.
#
# Add to printer.cfg:
# [servo_enable_delay]
# axes: stepper_x, stepper_y, dual_carriage, stepper_y1
# delay: 0.5  # seconds

import logging

class ServoEnableDelay:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.delay = config.getfloat('delay', 0.5, above=0.)
        self.axes = [a.strip() for a in config.get('axes').split(',')]
        self.printer.register_event_handler(
            'klippy:connect', self._handle_connect)
        self.printer.register_event_handler(
            'homing:home_rails_begin', self._handle_home_rails_begin)
        logging.info(
            "ServoEnableDelay: configured for axes %s with %.3fs delay",
            self.axes, self.delay)

    def _handle_connect(self):
        stepper_enable = self.printer.lookup_object('stepper_enable')
        for axis in self.axes:
            try:
                stepper_enable.lookup_enable(axis)
                logging.info(
                    "ServoEnableDelay: verified axis %s exists", axis)
            except Exception as e:
                logging.warning(
                    "ServoEnableDelay: axis %s not found: %s", axis, str(e))

    def _handle_home_rails_begin(self, homing_state, rails):
        # Get the names of all steppers on the rails being homed
        rail_steppers = []
        for rail in rails:
            for stepper in rail.get_steppers():
                rail_steppers.append(stepper.get_name())

        # Check if any of the rails being homed are servo axes
        servo_axes_homing = [a for a in self.axes if a in rail_steppers]

        if servo_axes_homing:
            toolhead = self.printer.lookup_object('toolhead')
            gcode = self.printer.lookup_object('gcode')
            logging.info(
                "ServoEnableDelay: servo axes %s detected in homing move, "
                "dwelling %.3fs", servo_axes_homing, self.delay)
            gcode.respond_info(
                "Step servo: enabling %s, waiting %.0fms for drives to "
                "initialise" % (', '.join(servo_axes_homing),
                                self.delay * 1000))
            toolhead.dwell(self.delay)

def load_config(config):
    return ServoEnableDelay(config)
