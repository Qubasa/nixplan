# A unit that is scheduled rather than long-running.
#
# It exists so that one boot can observe the difference between installing a
# trigger and running a job: deploying this entry arms a timer and starts
# nothing, and the file the job would write is the evidence that it did not run.
{ coreutils }:

{ settings, ... }:
{
  platforms = [ "x86_64-linux" ];

  impl = _: {
    closure = [ coreutils ];

    # `daily` rather than a near time on purpose: the next elapse has to stay in
    # the future for the whole run, so that "the timer is armed" and "the job has
    # not run" are two facts about the same machine at the same moment.
    units.rotate = {
      command = "${coreutils}/bin/touch ${settings.markerPath}";
      schedule = "daily";
      oneShot = true;
    };
  };
}
