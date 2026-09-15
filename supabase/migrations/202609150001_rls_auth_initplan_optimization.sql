-- DB-PERF-1B: make the authentication helper an InitPlan within current RLS policies.
--
-- This is intentionally policy-expression-only. ALTER POLICY preserves each
-- policy's existing name, target, command, roles, and permissive semantics.
-- No grants, revokes, tables, functions, triggers, or extension objects change.

-- Canonical public-table policies.
ALTER POLICY check_ins_read ON public.check_ins
  USING ((user_id = (select auth.uid())));

ALTER POLICY comments_delete ON public.comments
  USING ((author_id = (select auth.uid())));
ALTER POLICY comments_insert ON public.comments
  WITH CHECK (((author_id = (select auth.uid())) AND (status = 'visible'::social_content_status) AND (EXISTS (SELECT 1 FROM locations l WHERE ((l.id = comments.location_id) AND ((l.owner_id = (select auth.uid())) OR ((l.status = 'approved'::location_status) AND (l.visibility = ANY (ARRAY['public'::location_visibility, 'unlisted'::location_visibility])))))))));
ALTER POLICY comments_read ON public.comments
  USING (((author_id = (select auth.uid())) OR ((status = 'visible'::social_content_status) AND (EXISTS (SELECT 1 FROM locations l WHERE ((l.id = comments.location_id) AND ((l.owner_id = (select auth.uid())) OR ((l.status = 'approved'::location_status) AND (l.visibility = ANY (ARRAY['public'::location_visibility, 'unlisted'::location_visibility]))))))))));
ALTER POLICY comments_update ON public.comments
  USING ((author_id = (select auth.uid())))
  WITH CHECK ((author_id = (select auth.uid())));

ALTER POLICY follows_delete ON public.follows
  USING ((follower_id = (select auth.uid())));
ALTER POLICY follows_insert ON public.follows
  WITH CHECK ((follower_id = (select auth.uid())));

ALTER POLICY "Users can delete their friendships" ON public.friendships
  USING ((((select auth.uid()) = user_id_1) OR ((select auth.uid()) = user_id_2)));
ALTER POLICY "Users can insert their friendships" ON public.friendships
  WITH CHECK ((((select auth.uid()) = user_id_1) OR ((select auth.uid()) = user_id_2)));
ALTER POLICY "Users can update their friendships" ON public.friendships
  USING ((((select auth.uid()) = user_id_1) OR ((select auth.uid()) = user_id_2)));
ALTER POLICY "Users can view their friendships" ON public.friendships
  USING ((((select auth.uid()) = user_id_1) OR ((select auth.uid()) = user_id_2)));

ALTER POLICY location_categories_owner_delete ON public.location_categories
  USING ((EXISTS (SELECT 1 FROM locations l WHERE ((l.id = location_categories.location_id) AND (l.owner_id = (select auth.uid()))))));
ALTER POLICY location_categories_owner_insert ON public.location_categories
  WITH CHECK ((EXISTS (SELECT 1 FROM locations l WHERE ((l.id = location_categories.location_id) AND (l.owner_id = (select auth.uid()))))));

ALTER POLICY location_photos_owner_delete ON public.location_photos
  USING ((uploader_id = (select auth.uid())));
ALTER POLICY location_photos_owner_insert ON public.location_photos
  WITH CHECK (((uploader_id = (select auth.uid())) AND (EXISTS (SELECT 1 FROM locations l WHERE ((l.id = location_photos.location_id) AND (l.owner_id = (select auth.uid())))))));
ALTER POLICY location_photos_owner_update ON public.location_photos
  USING ((uploader_id = (select auth.uid())))
  WITH CHECK ((uploader_id = (select auth.uid())));
ALTER POLICY location_photos_read ON public.location_photos
  USING (((uploader_id = (select auth.uid())) OR (status = 'visible'::social_content_status)));

ALTER POLICY locations_delete ON public.locations
  USING (((owner_id = (select auth.uid())) AND (status = ANY (ARRAY['draft'::location_status, 'rejected'::location_status]))));
ALTER POLICY locations_insert ON public.locations
  WITH CHECK (((owner_id = (select auth.uid())) AND (status = 'draft'::location_status)));
ALTER POLICY locations_read ON public.locations
  USING (((owner_id = (select auth.uid())) OR ((status = 'approved'::location_status) AND (visibility = ANY (ARRAY['public'::location_visibility, 'unlisted'::location_visibility])))));
ALTER POLICY locations_update ON public.locations
  USING (((owner_id = (select auth.uid())) AND (status = ANY (ARRAY['draft'::location_status, 'rejected'::location_status]))))
  WITH CHECK (((owner_id = (select auth.uid())) AND (status = ANY (ARRAY['draft'::location_status, 'rejected'::location_status]))));

ALTER POLICY messages_friend_insert ON public.messages
  WITH CHECK (((sender_id = ((select auth.uid()))::text) AND (receiver_id <> ((select auth.uid()))::text) AND (EXISTS (SELECT 1 FROM friendships f WHERE ((f.status = 'accepted'::text) AND (((f.user_id_1 = (select auth.uid())) AND ((f.user_id_2)::text = messages.receiver_id)) OR ((f.user_id_2 = (select auth.uid())) AND ((f.user_id_1)::text = messages.receiver_id))))))));
ALTER POLICY messages_friend_read ON public.messages
  USING ((((sender_id = ((select auth.uid()))::text) OR (receiver_id = ((select auth.uid()))::text)) AND (EXISTS (SELECT 1 FROM friendships f WHERE ((f.status = 'accepted'::text) AND ((((f.user_id_1)::text = messages.sender_id) AND ((f.user_id_2)::text = messages.receiver_id)) OR (((f.user_id_2)::text = messages.sender_id) AND ((f.user_id_1)::text = messages.receiver_id))))))));

ALTER POLICY notifications_read ON public.notifications
  USING ((user_id = (select auth.uid())));
ALTER POLICY notifications_update ON public.notifications
  USING ((user_id = (select auth.uid())))
  WITH CHECK ((user_id = (select auth.uid())));

ALTER POLICY profiles_update_own ON public.profiles
  USING ((id = (select auth.uid())))
  WITH CHECK ((id = (select auth.uid())));
ALTER POLICY profiles_update_self ON public.profiles
  USING ((id = (select auth.uid())))
  WITH CHECK ((id = (select auth.uid())));

ALTER POLICY "Authenticated users can insert reviews." ON public.reviews
  WITH CHECK (((select auth.uid()) = user_id));
ALTER POLICY "Users can delete their own reviews." ON public.reviews
  USING (((select auth.uid()) = user_id));

ALTER POLICY achievements_read ON public.user_achievements
  USING ((user_id = (select auth.uid())));
ALTER POLICY user_achievements_read_own ON public.user_achievements
  USING ((user_id = (select auth.uid())));
ALTER POLICY user_settings_self ON public.user_settings
  USING ((user_id = (select auth.uid())))
  WITH CHECK ((user_id = (select auth.uid())));

-- Current Storage object policies. Bucket and path predicates are unchanged.
ALTER POLICY avatars_owner_delete ON storage.objects
  USING (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = ((select auth.uid()))::text)));
ALTER POLICY avatars_owner_insert ON storage.objects
  WITH CHECK (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = ((select auth.uid()))::text)));
ALTER POLICY avatars_owner_update ON storage.objects
  USING (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = ((select auth.uid()))::text)))
  WITH CHECK (((bucket_id = 'avatars'::text) AND ((storage.foldername(name))[1] = ((select auth.uid()))::text)));
ALTER POLICY location_images_authenticated_upload ON storage.objects
  WITH CHECK (((bucket_id = 'location_images'::text) AND ((storage.foldername(name))[1] = ((select auth.uid()))::text)));
ALTER POLICY location_images_owner_delete ON storage.objects
  USING (((bucket_id = 'location_images'::text) AND ((storage.foldername(name))[1] = ((select auth.uid()))::text)));

-- Route editor policies.
ALTER POLICY routes_owner_select ON public.routes
  USING ((author_id = ((select auth.uid()))::text));
ALTER POLICY routes_owner_insert ON public.routes
  WITH CHECK (((author_id = ((select auth.uid()))::text) AND (jsonb_array_length(points) >= 2)));
ALTER POLICY routes_owner_update ON public.routes
  USING ((author_id = ((select auth.uid()))::text))
  WITH CHECK (((author_id = ((select auth.uid()))::text) AND (jsonb_array_length(points) >= 2)));
ALTER POLICY routes_owner_delete ON public.routes
  USING ((author_id = ((select auth.uid()))::text));

-- Chat per-user hidden-state policies.
ALTER POLICY message_user_state_select ON public.message_user_state
  USING ((user_id = (select auth.uid())));
ALTER POLICY message_user_state_insert ON public.message_user_state
  WITH CHECK (((user_id = (select auth.uid())) AND (EXISTS (SELECT 1 FROM public.messages m WHERE ((m.id = message_user_state.message_id) AND ((m.sender_id = ((select auth.uid()))::text) OR (m.receiver_id = ((select auth.uid()))::text)))))));
ALTER POLICY message_user_state_delete ON public.message_user_state
  USING ((user_id = (select auth.uid())));

-- GPS policies only: ACL hardening is intentionally not modified.
ALTER POLICY trips_select ON public.trips
  USING ((owner_id = (select auth.uid())));
ALTER POLICY trips_insert ON public.trips
  WITH CHECK ((owner_id = (select auth.uid())));
ALTER POLICY trips_update ON public.trips
  USING ((owner_id = (select auth.uid())))
  WITH CHECK ((owner_id = (select auth.uid())));
ALTER POLICY trips_delete ON public.trips
  USING ((owner_id = (select auth.uid())));

ALTER POLICY recorded_routes_select ON public.recorded_routes
  USING ((owner_id = (select auth.uid())));
ALTER POLICY recorded_routes_insert ON public.recorded_routes
  WITH CHECK (((owner_id = (select auth.uid())) AND ((trip_id IS NULL) OR (EXISTS (SELECT 1 FROM public.trips t WHERE ((t.id = recorded_routes.trip_id) AND (t.owner_id = (select auth.uid()))))))));
ALTER POLICY recorded_routes_update ON public.recorded_routes
  USING ((owner_id = (select auth.uid())))
  WITH CHECK (((owner_id = (select auth.uid())) AND ((trip_id IS NULL) OR (EXISTS (SELECT 1 FROM public.trips t WHERE ((t.id = recorded_routes.trip_id) AND (t.owner_id = (select auth.uid()))))))));
ALTER POLICY recorded_routes_delete ON public.recorded_routes
  USING ((owner_id = (select auth.uid())));

ALTER POLICY route_points_select ON public.route_points
  USING ((EXISTS (SELECT 1 FROM public.recorded_routes r WHERE ((r.id = route_points.recorded_route_id) AND (r.owner_id = (select auth.uid()))))));
ALTER POLICY route_points_insert ON public.route_points
  WITH CHECK ((EXISTS (SELECT 1 FROM public.recorded_routes r WHERE ((r.id = route_points.recorded_route_id) AND (r.owner_id = (select auth.uid()))))));

ALTER POLICY route_waypoints_select ON public.route_waypoints
  USING ((owner_id = (select auth.uid())));
ALTER POLICY route_waypoints_insert ON public.route_waypoints
  WITH CHECK (((owner_id = (select auth.uid())) AND (EXISTS (SELECT 1 FROM public.recorded_routes r WHERE ((r.id = route_waypoints.recorded_route_id) AND (r.owner_id = (select auth.uid())))))));
ALTER POLICY route_waypoints_update ON public.route_waypoints
  USING ((owner_id = (select auth.uid())))
  WITH CHECK ((owner_id = (select auth.uid())));
ALTER POLICY route_waypoints_delete ON public.route_waypoints
  USING ((owner_id = (select auth.uid())));

ALTER POLICY recorded_route_events_select ON public.recorded_route_events
  USING ((EXISTS (SELECT 1 FROM public.recorded_routes r WHERE ((r.id = recorded_route_events.recorded_route_id) AND (r.owner_id = (select auth.uid()))))));
ALTER POLICY recorded_route_events_insert ON public.recorded_route_events
  WITH CHECK ((EXISTS (SELECT 1 FROM public.recorded_routes r WHERE ((r.id = recorded_route_events.recorded_route_id) AND (r.owner_id = (select auth.uid()))))));
