/* Tests for the Camera class.
 *
 * Objective-C on purpose: Camera is the whole of this submodule's instrumented
 * surface, and it is also the case harness.h was designed for -- cases register
 * through __attribute__((constructor)), so the same header works from a .m
 * translation unit with no C++ in sight.
 *
 * Camera stores a position and a look-at point in cartesian coordinates and
 * converts to spherical on demand, with theta = atan2(z, x) measured in the
 * xz-plane and phi = atan2(y, hypot(x, z)) as elevation. Expected values below
 * are derived from that convention, not read off a run, except where a case
 * says otherwise.
 *
 * No -fobjc-arc in this submodule's cflags, so these are manual-retain-release
 * translation units. The cameras are deliberately not released: the suite is a
 * short-lived binary and a release here would fail to compile if the submodule
 * ever moves to ARC.
 */

#import "harness.h"

#import "Camera.h"

static const float kTol = 1e-3f;

/* Builds a camera looking at the origin from (x, y, z). */
static Camera *cameraAt(float x, float y, float z)
{
    Camera *camera = [[Camera alloc] init];
    [camera lookAt_x:0.0f y:0.0f z:0.0f];
    [camera positionAt_x:x y:y z:z];
    return camera;
}

TEST(distance_is_the_length_of_position_minus_lookat)
{
    /* 3-4-5, so the expected value does not depend on a square root being
     * evaluated the same way twice. */
    Camera *camera = cameraAt(3.0f, 0.0f, 4.0f);
    CHECK_NEAR([camera getDistance], 5.0f, kTol);
}

TEST(distance_is_zero_when_position_and_lookat_coincide)
{
    Camera *camera = [[Camera alloc] init];
    [camera lookAt_x:2.0f y:3.0f z:4.0f];
    [camera positionAt_x:2.0f y:3.0f z:4.0f];
    CHECK_NEAR([camera getDistance], 0.0f, kTol);
}

TEST(x_degrees_is_the_azimuth_in_the_xz_plane)
{
    /* atan2(4, 3) = 53.13 degrees. */
    Camera *camera = cameraAt(3.0f, 0.0f, 4.0f);
    CHECK_NEAR([camera getXDegrees], 53.130102f, 1e-2f);

    /* Straight down +x is zero, straight down +z is a quarter turn. */
    CHECK_NEAR([cameraAt(5.0f, 0.0f, 0.0f) getXDegrees], 0.0f, kTol);
    CHECK_NEAR([cameraAt(0.0f, 0.0f, 5.0f) getXDegrees], 90.0f, 1e-2f);
}

TEST(y_degrees_is_the_elevation_above_the_xz_plane)
{
    /* In the plane, elevation is zero; straight up is a quarter turn. */
    CHECK_NEAR([cameraAt(3.0f, 0.0f, 4.0f) getYDegrees], 0.0f, kTol);
    CHECK_NEAR([cameraAt(0.0f, 5.0f, 0.0f) getYDegrees], 90.0f, 1e-2f);

    /* Equal horizontal and vertical extent is half of that again. */
    CHECK_NEAR([cameraAt(3.0f, 3.0f, 0.0f) getYDegrees], 45.0f, 1e-2f);
}

TEST(set_distance_moves_along_the_same_bearing)
{
    /* Setting r must not disturb theta or phi -- that is the whole point of
     * going through spherical coordinates to do it. */
    Camera *camera = cameraAt(3.0f, 0.0f, 4.0f);
    float before = [camera getXDegrees];

    [camera setDistance:10.0f];

    CHECK_NEAR([camera getDistance], 10.0f, kTol);
    CHECK_NEAR([camera getXDegrees], before, 1e-2f);
}

TEST(set_distance_clamps_a_degenerate_distance)
{
    /* Below 0.001 it snaps to 0.0001 rather than to zero, so that the bearing
     * stays recoverable instead of collapsing to atan2(0, 0). */
    Camera *camera = cameraAt(3.0f, 0.0f, 4.0f);
    [camera setDistance:0.0f];
    CHECK_NEAR([camera getDistance], 0.0001f, 1e-6f);

    [camera setDistance:-5.0f];
    CHECK_NEAR([camera getDistance], 0.0001f, 1e-6f);
}

TEST(rotate_clamps_elevation_short_of_the_pole)
{
    /* Past 89 degrees the world flips over, so the setter refuses to go there.
     * The comment in Camera.m says as much. */
    Camera *camera = cameraAt(5.0f, 0.0f, 0.0f);

    [camera rotateByDegrees_x:0.0f y:100.0f];
    CHECK_NEAR([camera getYDegrees], 89.0f, 1e-2f);

    [camera rotateByDegrees_x:0.0f y:-100.0f];
    CHECK_NEAR([camera getYDegrees], -89.0f, 1e-2f);
}

TEST(rotate_preserves_distance)
{
    Camera *camera = cameraAt(3.0f, 0.0f, 4.0f);
    [camera rotateByDegrees_x:37.0f y:12.0f];
    CHECK_NEAR([camera getDistance], 5.0f, 1e-2f);
}

TEST(rotate_sets_absolute_angles_despite_its_name)
{
    /* CHARACTERIZATION -- pins current behaviour, not intended behaviour.
     *
     * rotateByDegrees_x:y: reads the current bearing into newPos and then
     * overwrites both angles with its arguments rather than adding to them, so
     * it is a setter with a mover's name. Applying it twice is therefore the
     * same as applying it once, which is the cheapest way to show it.
     *
     * Left alone: renaming it or making it relative is a behaviour change with
     * callers to check, and this commit adds tests. */
    Camera *once = cameraAt(5.0f, 0.0f, 0.0f);
    Camera *twice = cameraAt(5.0f, 0.0f, 0.0f);

    [once rotateByDegrees_x:30.0f y:10.0f];
    [twice rotateByDegrees_x:30.0f y:10.0f];
    [twice rotateByDegrees_x:30.0f y:10.0f];

    CHECK_NEAR([twice getXDegrees], [once getXDegrees], 1e-2f);
    CHECK_NEAR([twice getYDegrees], [once getYDegrees], 1e-2f);
    CHECK_NEAR([once getXDegrees], 30.0f, 1e-2f);
}

TEST(move_forwards_resets_the_distance_to_the_step)
{
    /* CHARACTERIZATION -- pins current behaviour, not intended behaviour.
     *
     * moveForwards: advances the position by `distance` along the view
     * direction, then sets mLookAt to position + the same vector. So the
     * look-at point is dragged along and the camera's distance ends up equal to
     * the step just taken, whatever it was before. A move that preserved the
     * distance would leave mLookAt alone. */
    Camera *camera = [[Camera alloc] init];
    [camera positionAt_x:0.0f y:0.0f z:0.0f];
    [camera lookAt_x:0.0f y:0.0f z:10.0f];
    CHECK_NEAR([camera getDistance], 10.0f, kTol);

    [camera moveForwards:2.0f];
    CHECK_NEAR([camera getDistance], 2.0f, kTol);
}

TEST(move_backwards_reverses_a_move_forwards_in_position)
{
    Camera *camera = [[Camera alloc] init];
    [camera positionAt_x:0.0f y:0.0f z:0.0f];
    [camera lookAt_x:0.0f y:0.0f z:10.0f];

    [camera moveForwards:3.0f];
    float advanced = [camera getDistance];
    [camera moveBackwards:3.0f];

    /* Both steps are the same length along the same bearing. */
    CHECK_NEAR(advanced, 3.0f, kTol);
    CHECK_NEAR([camera getDistance], 3.0f, kTol);
}
