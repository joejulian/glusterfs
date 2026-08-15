#!/bin/bash
# shellcheck disable=SC1091

. "$(dirname "$0")/../../include.rc"
. "$(dirname "$0")/../../volume.rc"

cleanup;

TEST glusterd
TEST pidof glusterd
TEST "$CLI" volume create "$V0" replica 3 "${H0}:${B0}/${V0}"{0,1,2}
TEST "$CLI" volume set "$V0" feature.simple-quota-pass-through false
TEST "$CLI" volume set "$V0" cluster.metadata-self-heal on
TEST "$CLI" volume start "$V0"

TEST "$GFS" --volfile-id="/$V0" --volfile-server="$H0" "$M0"
TEST "$GFS" --volfile-id="/$V0" --volfile-server="$H0" \
    --client-pid=-14 --process-name=quota "$M1"

TEST mkdir "$M0/marked"
TEST mkdir "$M0/missed"
TEST setfattr -n trusted.glusterfs.namespace -v true "$M1/marked"
TEST setfattr -n trusted.gfs.squota.limit -v 1048576 "$M1/marked"

TEST kill_brick "$V0" "$H0" "${B0}/${V0}2"
EXPECT_WITHIN "$PROCESS_DOWN_TIMEOUT" "0" afr_child_up_status "$V0" 2

# Queue metadata heal on a namespace-marked directory while one brick is down.
TEST chmod 0750 "$M0/marked"

# The namespace operation on this pre-existing directory misses brick 2. Heal
# must restore the source marker there, which rules out globally ignoring it.
TEST setfattr -n trusted.glusterfs.namespace -v true "$M1/missed"

TEST "$CLI" volume start "$V0" force
EXPECT_WITHIN "$PROCESS_UP_TIMEOUT" "1" afr_child_up_status "$V0" 2
EXPECT_WITHIN "$CHILD_UP_TIMEOUT" "1" afr_child_up_status_in_shd "$V0" 2

# The protected namespace marker must not make the sink's bulk removexattr fail
# with ENOTSUP when the self-heal daemon processes both directories.
TEST stat "$M0/marked"
TEST stat "$M0/missed"
TEST "$CLI" volume heal "$V0"
EXPECT_WITHIN "$HEAL_TIMEOUT" "^0$" get_pending_heal_count "$V0"

EXPECT "750" stat -c %a "${B0}/${V0}0/marked"
EXPECT "750" stat -c %a "${B0}/${V0}1/marked"
EXPECT "750" stat -c %a "${B0}/${V0}2/marked"
EXPECT "true" getfattr --only-values -n trusted.glusterfs.namespace \
    "${B0}/${V0}0/marked"
EXPECT "true" getfattr --only-values -n trusted.glusterfs.namespace \
    "${B0}/${V0}1/marked"
EXPECT "true" getfattr --only-values -n trusted.glusterfs.namespace \
    "${B0}/${V0}2/marked"
EXPECT "true" getfattr --only-values -n trusted.glusterfs.namespace \
    "${B0}/${V0}0/missed"
EXPECT "true" getfattr --only-values -n trusted.glusterfs.namespace \
    "${B0}/${V0}1/missed"
EXPECT "true" getfattr --only-values -n trusted.glusterfs.namespace \
    "${B0}/${V0}2/missed"

EXPECT_WITHIN "$UMOUNT_TIMEOUT" "Y" force_umount "$M0"
EXPECT_WITHIN "$UMOUNT_TIMEOUT" "Y" force_umount "$M1"

cleanup;

exit 0
