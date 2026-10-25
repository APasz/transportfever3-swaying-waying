global enum SwayingWayingCarrier
    "RAIL"
    "TRAM"
end

global enum SwayingWayingMotionProfile
    "QUICK"
    "DEFAULT"
    "SLOW"
end

global record SwayingWaying
    type RawTable = {any: any}
    type ModParams = {string: integer}
    type AllModParams = {string: ModParams}

    type Logger = ModLogging.Logger

    record CacheEntry<K, V>
        key: K
        value: V
        previous: CacheEntry<K, V> | nil
        next: CacheEntry<K, V> | nil
    end

    record BoundedCache<K, V>
        capacity: integer
        count: integer
        entries: {K: CacheEntry<K, V>}
        newest: CacheEntry<K, V> | nil
        oldest: CacheEntry<K, V> | nil
    end

    record Cache
        create: function<K, V>(integer): BoundedCache<K, V>
        get: function<K, V>(BoundedCache<K, V>, K): V | nil
        put: function<K, V>(BoundedCache<K, V>, K, V)
    end

    record Values
        clamp: function(number, number, number): number
        asTable: function(any): RawTable | nil
        asArray: function(any): {any} | nil
        nodeSuffix: function(string): string
        nonnegative: function(any): boolean
        wheelbase: function(any): boolean
        positiveInteger: function(any): integer | nil
        arraySize: function(RawTable): integer | nil
    end

    record PlacementExtent
        minimum: number
        maximum: number
        count: integer
    end

    record PlacementData
        groups: {string: boolean}
        extents: {string: PlacementExtent}
    end

    record Vector3
        x: number
        y: number
        z: number
    end

    enum SectionAxes
        "model"
        "group"
    end

    record ModelSection
        group: string
        groupsByLod: {integer: string} | nil
        lag: number
        wheelbase: number | nil
        pivot: Vector3 | nil
        axes: SectionAxes
        index: integer
    end

    record ModelAuthoring
        options: function(string, RawTable): ModelOptions
        validateLods: function(string, ModelOptions, integer): boolean
        group: function(ModelSection, integer): string
    end

    record ModelOptions
        valid: boolean
        sections: {ModelSection} | nil
        skipFromLod: integer | nil
        wheelbase: number | nil
    end

    record VehicleMotionSettings
        swayEnabled: boolean
        cameraEnabled: boolean
        swayFactor: number
        profile: SwayingWayingMotionProfile
    end

    record ModelPolicy
        options: function(string, RawTable): ModelOptions
        carrier: function(RawTable): SwayingWayingCarrier | nil
        vehicleSettings: function(string, RawTable, number): VehicleMotionSettings | nil
        lodCount: function(string, {any}, RawTable | nil, ModelOptions, any): integer, integer | nil
        authoredSway: function(RawTable, RawTable | nil): boolean
        axisSign: function({any}): number
        pivot: function(RawTable): number
        wheelbase: function(RawTable, PlacementData, string | nil): number
        placement: function({ModelReference}): PlacementData
        axles: function(RawTable): {string: boolean}
        referencesAnimationFile: function(any, string): boolean
    end

    enum ModelFailure
        "invalid active LOD root"
        "invalid section groups"
        "body groups could not be identified"
        "no body groups wrapped"
    end

    record ModelReports
        applied: function(ModelContext, integer, integer, integer)
        active: function(ModelContext, integer, any, ModelNode | nil, {string: boolean} | nil, integer, ModelFailure | nil)
        inactive: function(ModelContext, {any}, integer)
        skipped: function(ModelContext, {any}, integer, ModelFailure)
    end

    record ModelReporting
        create: function(SwayingWaying.Logger, boolean): ModelReports
    end

    record ModelCompatibility
        configure: function(AllModParams | nil)
        isModEnabled: function(string): boolean
        wrapperFor: function(string): string
        defaultFor: function(SwayingWayingCarrier): string
        prepare: function(string, any)
        refresh: function(string, RawTable, string, RawTable)
        isDirect: function(any): boolean
        isBodyContainer: function(string): boolean
    end

    record Config
        speedDependent: boolean
        intensity: number
        rollBalance: number
        pitchBalance: number
        heaveBalance: number
        curveLeanIntensity: number
        curveSamplingDistance: number
        trackInfluence: number
        samplingDistance: number
        vehicleVariation: number
    end

    enum SettingId
        "enabled"
        "cameras"
        "modelDiagnostics"
        "intensity"
        "rollBalance"
        "pitchBalance"
        "heaveBalance"
        "curveLeanIntensity"
        "curveSamplingDistance"
        "trackInfluence"
        "samplingDistance"
        "vehicleVariation"
    end

    enum SwayMode
        "Off"
        "On"
        "Speedless Sway"
    end

    enum SettingControl
        "CheckBox"
        "Slider"
        "ComboBox"
    end

    record SettingDefinition
        id: SettingId
        key: string
        name: string
        tooltip: string
        uiType: SettingControl
        defaultIndex: integer
        values: {number}
        labels: {string}
    end

    record Settings
        read: function(AllModParams | nil): boolean, Config, boolean, CameraMode, boolean
        resolve: function(Config): Config
        describe: function(Config): string
        effectiveCameraMode: function(CameraMode, boolean): CameraMode
        definitions: {SettingDefinition}
    end

    enum CameraMode
        "Disabled"
        "Stable"
        "Sway"
        "Both"
    end

    record ModelLoadOptions
        swayEnabled: boolean
        cameraMode: CameraMode
        extraCameras: boolean | nil
    end

    record CameraConfig
        multipleCrewSeats: boolean
        hudEnabled: boolean
    end

    record CameraPosition
        group: string
        transf: {number}
        fov: number
    end

    record CameraView
        sourceGroup: string
        stableGroup: string
        pose: {number}
        fov: number
        crewSeat: integer | nil
    end

    enum CameraKind
        "Model"
        "Stable"
        "Sway"
    end

    record CameraDescriptor
        index: integer
        kind: CameraKind
        crewSeat: integer | nil
        pose: {number}
    end

    record CameraHudMetadata
        schema: integer
        count: integer
        positions: {CameraDescriptor}
    end

    record HudPoint
        x: number
        y: number
        z: number
    end

    record CameraHudPolicy
        read: function(any): CameraHudMetadata | nil
        finitePoint: function(HudPoint): boolean
        localEye: function(Mat4f, HudPoint): HudPoint | nil
        contains: function(HudPoint, HudPoint, HudPoint, HudPoint): boolean
        cameraAt: function(CameraHudMetadata, HudPoint, HudPoint): CameraDescriptor | nil, boolean
    end

    record CameraPlan
        mode: CameraMode
        views: {CameraView}
        placementGroups: {string: boolean}
    end

    record CameraAdditions
        positions: {CameraPosition}
        rests: {string: {number}}
    end

    record ModelCameras
        positions: function(RawTable): {any}
        validate: function(RawTable, any)
        capture: function(string, RawTable, CameraMode, ?boolean): CameraPlan
        apply: function(string, RawTable, CameraPlan, {string: string}, WrapperRegistry | nil): CameraAdditions, boolean
    end

    record CameraCompatibility
        reset: function()
        prepare: function(string, RawTable, boolean): boolean, boolean
        refresh: function(string, RawTable, CameraAdditions)
    end

    record FileAnimationParams
        id: string
    end

    enum FileAnimationKind
        "FILE_REF"
    end

    record FileAnimation
        type: FileAnimationKind
        params: FileAnimationParams
    end

    record ModelNode
        name: string | nil
        transf: {number} | nil
        children: {ModelNode} | nil
        animations: {string: any} | nil
        mesh: string | nil
        materials: {string} | nil
        skin: any
        skinMaterials: {string} | nil
        meshes: any
    end

    record WrappedNode
        swayName: string
        pitchName: string
        rollName: string
        contentName: string
    end

    record MotionAnimations
        roll: string
        pitch: string | nil
        heave: string | nil
    end

    record MotionFrame
        toBody: {number}
        fromBody: {number}
    end

    record WrapperRegistry
        names: {string: WrappedNode}
        reserved: {string: boolean}
    end

    record NodeIndex
        names: {string: {ModelNode}}
        parents: {ModelNode: ModelNode}
        axles: {ModelNode: boolean}
        swayable: {ModelNode: boolean}
        rigid: {ModelNode: boolean}
        seen: {ModelNode: boolean}
    end

    record ModelAnalysis
        index: function({any}, {string: boolean}, {string: boolean}): {ModelNode: NodeIndex}
        activeRoots: function(string, {any}, integer): {ModelNode} | nil
        validateSections: function(string, {ModelNode}, {ModelSection}, boolean, {ModelNode: NodeIndex}): boolean
        placementTargets: function({ModelNode}, {string: boolean}, {string: boolean}, {ModelNode: NodeIndex}): {{string: boolean}} | nil
        bodyTargets: function({ModelNode}, {string: boolean}, {ModelNode: NodeIndex}): {{string: boolean}} | nil
        sections: function(string, {ModelNode}, {string: boolean}, PlacementData, {ModelNode: NodeIndex}): {ModelSection} | nil
    end

    record ModelContext
        fileName: string
        originalTransformator: string
        axleNames: {string: boolean}
        placementGroups: {string: boolean}
        pivot: number
        references: ReferenceTargets
        wrappers: WrapperRegistry
        indices: {ModelNode: NodeIndex}
    end

    record LodContext
        model: ModelContext
        fixedBranches: {ModelNode: boolean}
        bodyGroups: {string: boolean} | nil
    end

    record ModelNodes
        get: function(any): ModelNode | nil
        validate: function(any, ?{ModelNode: NodeIndex}): {ModelNode: {string: integer}}
        identity: function(number): {number}
        transform: function(ModelNode | nil): {number}
        multiply: function({number}, {number}): {number}
        inverse: function({number}): {number} | nil
        validTransform: function(any): boolean
        name: function(ModelNode, string): string
        hasContent: function(ModelNode): boolean
        countNamed: function(any, string, integer): integer
        ensureAttachmentAnchor: function(ModelNode, string)
        ensureMotionAnchor: function(ModelNode, number, WrappedNode)
        ensureRootMotionAnchor: function(ModelNode, number, WrapperRegistry)
        registry: function({ModelNode: NodeIndex}): WrapperRegistry
        wrapperNames: function(string, boolean, WrapperRegistry): WrappedNode
        sectionFrame: function(ModelNode, NodeIndex, ModelSection, number, integer, ?number): MotionFrame
        wrap: function(ModelNode, LodContext, boolean, MotionAnimations | nil, MotionFrame | nil, ?WrappedNode): WrappedNode | nil
        wrapLocator: function(ModelNode, MotionAnimations | nil, WrapperRegistry, ?MotionFrame, ?WrappedNode): WrappedNode | nil
    end

    record ModelTransaction
        run: function(any, function(any): boolean): any
    end

    record ReferenceTargets
        attachments: {string: string}
        placements: {string: string}
        meshes: {string: string}
    end

    enum ReferenceKind
        "attachment"
        "placement"
        "mesh"
    end

    record ModelReference
        owner: RawTable
        field: string
        target: string
        kind: ReferenceKind
    end

    record ModelReferences
        collect: function(RawTable): {ModelReference}
        hasReferences: function({ModelReference}, ReferenceTargets): boolean
        retarget: function({ModelReference}, ReferenceTargets)
        validate: function({ModelReference}, ReferenceTargets, {ModelNode: NodeIndex}, {ModelNode: {string: integer}})
        defaultLabels: function({any: any}): {{any: any}}
    end

    record MotionConfig
        roll: boolean
        pitch: boolean
        heave: boolean
        shortWave: boolean
        longWave: boolean
        thirdWave: boolean
        irregularity: boolean
        curveLean: boolean
        trackResponse: boolean
        vehicleResponse: boolean
        speedEnvelope: boolean
        carriageLag: boolean
        sectionLag: boolean
    end

    record SpacingProbe
        inspect: function(integer | nil)
    end

    record SpacingBridgeProbe
        test: function(integer)
        clear: function(integer)
    end

    record MotionSettings
        rollIntensity: number
        pitchIntensity: number
        heaveIntensity: number
        curveLeanIntensity: number
        modelAxisSign: number
        profile: SwayingWayingMotionProfile
        secondaryMotionEnabled: boolean
    end

    record RuntimeSectionConfig
        lag: number
        wheelbase: number
    end

    record ModelRuntimeConfig
        schema: integer
        revision: integer
        modelFile: string
        originalTransformator: string
        carrier: SwayingWayingCarrier
        profile: SwayingWayingMotionProfile
        axisReversed: boolean
        vehicleFactor: number
        wheelbase: number
        settings: Config
        sections: {RuntimeSectionConfig}
    end

    record RuntimeSection
        lag: number
        geometry: MotionGeometry
        animations: MotionAnimations
    end

    record CompiledMotion
        modelFile: string
        speedDependent: boolean
        trackInfluence: number
        samplingDistance: number
        curveSamplingDistance: number
        vehicleVariation: number
        vehicleFactor: number
        revision: integer
        motion: MotionSettings
        proceduralMotionEnabled: boolean
        secondaryMotionEnabled: boolean
        curveLeanEnabled: boolean
        sections: {RuntimeSection}
    end

    record RuntimeModel
        source: ModelRuntimeConfig
        revision: integer
        compiled: CompiledMotion | nil
        originLoaded: boolean
        origin: Origin | nil
    end

    record CarriageState
        purchaseTime: integer
        model: CompiledMotion
        sample: MotionSample
        responseTime: integer | nil
        motionVelocity: number
        curveVelocity: number
        curveSampleDistance: number | nil
        curvature: number | nil
        waves: CarriageWaves | nil
        waveBasis: WaveBasis | nil
    end

    record MotionResponse
        update: function(CarriageState, integer, number, number)
        neutral: function(CarriageState): boolean
    end

    record CurveResponse
        tilt: function(Transformator.LandVehicleScriptingApi, number, boolean, CarriageState, number): number, number | nil
    end

    type CurvatureObserver = function(TransformatorParams, number | nil): boolean

    record CurvatureProbe
        observe: CurvatureObserver | nil
    end

    type LodObserver = function(TransformatorParams, Transformator.TransfOutput, string): boolean

    record LodProbe
        observe: LodObserver | nil
    end

    record AnimationBindings
        get: function(integer, boolean): MotionAnimations
    end

    record RuntimeConfig
        read: function(TransformatorParams): ModelRuntimeConfig
        validate: function(ModelRuntimeConfig): Config
    end

    record RuntimeState
        get: function(ModelRuntimeConfig, integer, integer): CarriageState | nil
        model: function(ModelRuntimeConfig): RuntimeModel
    end

    record MotionSample
        motionScale: number
        distance: number
        phaseSeed: integer
        sharedDistance: number
        sharedPhaseSeed: integer
        sharedAxisReversed: boolean
        curveTilt: number
        swayFactor: number
        shortWeight: number
        waves: CarriageWaves | nil
        irregularity: IrregularitySamples | nil
    end

    record WaveValues
        shortSin: number
        shortCos: number
        longSin: number
        longCos: number
        thirdSin: number
        thirdCos: number
    end

    record WaveBasis
        consist: integer
        distance: number | nil
        sharedDistance: number | nil
        reused: boolean
        shared: boolean
        shortDistance: number | nil
        longDistance: number | nil
        thirdDistance: number | nil
        values: WaveValues
        shortWaveLength: number
        thirdWaveLength: number
    end

    record WaveRotation
        rollSin: number
        rollCos: number
        heaveSin: number
        heaveCos: number
        pitchSin: number
        pitchCos: number
    end

    record SectionWaveRotations
        geometry: MotionGeometry
        shortWave: WaveRotation
        longWave: WaveRotation
        thirdWave: WaveRotation
    end

    record CarriageWaves
        phaseSeed: integer
        longPhaseSeed: integer
        carriageLag: number
        sharedAxisReversed: boolean
        sectionLagEnabled: boolean
        basis: WaveBasis
        rotations: {SectionWaveRotations}
        rotation: SectionWaveRotations
    end

    record MotionGeometry
        profile: SwayingWayingMotionProfile
        wheelbase: number
        shortHalfSin: number
        shortHalfCos: number
        longHalfSin: number
        longHalfCos: number
        thirdHalfSin: number
        thirdHalfCos: number
    end

    record IrregularityCache
        seed: integer | nil
        detailCell: number | nil
        broadCell: number | nil
        detailStart: number
        detailDelta: number
        broadStart: number
        broadDelta: number
    end

    record IrregularitySamples
        lateral: IrregularityCache
        front: IrregularityCache
        rear: IrregularityCache
        spacingLateral: IrregularityCache
        spacingFront: IrregularityCache
        spacingRear: IrregularityCache
    end

    record Irregularity
        blend: function(number, number): number
        create: function(): IrregularitySamples
        lateral: function(number, integer, ?IrregularityCache): number
        vertical: function(number, integer, ?IrregularityCache): number
        warp: function(number, integer, ?IrregularityCache): number
    end

    record Constants
        RUNTIME_PARAM: string
        RUNTIME_SCHEMA: integer
        ROOT_NODE: string
        MAX_MODEL_NODE_DEPTH: integer
        MOD_ID: string
        SWAY_ANIMATION: string
        PITCH_ANIMATION: string
        HEAVE_ANIMATION: string
        SWAY_SECTION_ANIMATION_PREFIX: string
        PITCH_SECTION_ANIMATION_PREFIX: string
        HEAVE_SECTION_ANIMATION_PREFIX: string
        AUTHORED_SWAY_ANIMATION: string
        AUTHORED_TENDER_SWAY_ANIMATION: string
        SWAY_NODE: string
        PITCH_NODE: string
        ROLL_NODE: string
        SWAY_CONTENT_NODE: string
        BASE_TILT_ANIMATION: string
        PITCH_ANIMATION_FILE: string
        HEAVE_ANIMATION_FILE: string
        TRAIN_TRANSFORMATOR: string
        TILTING_TRANSFORMATOR: string
        TRAM_TRANSFORMATOR: string
        ANY_TRANSFORMATOR: string
        ENABLED_PARAM_KEY: string
        CAMERAS_PARAM_KEY: string
        CAMERA_HUD_METADATA_KEY: string
        CAMERA_HUD_SCHEMA: integer
        INTENSITY_PARAM_KEY: string
        ROLL_BALANCE_PARAM_KEY: string
        PITCH_BALANCE_PARAM_KEY: string
        HEAVE_BALANCE_PARAM_KEY: string
        CURVE_LEAN_INTENSITY_PARAM_KEY: string
        CURVE_SAMPLING_DISTANCE_PARAM_KEY: string
        TRACK_INFLUENCE_PARAM_KEY: string
        SAMPLING_DISTANCE_PARAM_KEY: string
        VEHICLE_VARIATION_PARAM_KEY: string
        MODEL_DIAGNOSTICS_PARAM_KEY: string
        AUTHOR_METADATA_KEY: string
        TRACK_ROUGH_TAG: string
        TRACK_SMOOTH_TAG: string
        ROUGHER_TAG: string
        SMOOTHER_TAG: string
        QUICK_TAG: string
        SLOW_TAG: string
        NONE_TAG: string
        ONLY_CAMERA_TAG: string
        NO_CAMERA_TAG: string
        ROUGH_FACTOR: number
        SMOOTH_FACTOR: number
        MIN_MOTION_SPEED: number
        MIN_WHEELBASE: number
        MAX_WHEELBASE: number
        DEFAULT_WHEELBASE: number
        NEUTRAL_TRACK_SHORT_WEIGHT: number
        MAX_BALANCE: number
        MAX_TRACK_INFLUENCE: number
        MAX_VEHICLE_VARIATION: number
        MAX_SECTION_COUNT: integer
        MAX_RUNTIME_VEHICLE_STATES: integer
        MIN_SHARED_WAVE_CARRIAGES: integer
        DEFAULT_SAMPLE_DISTANCE: number

    end

    record Motion
        speedFactor: function(number, SwayingWayingMotionProfile, ?boolean): number
        hasSecondaryMotion: function(MotionSettings): boolean
        hasProceduralMotion: function(MotionSettings): boolean
        swayDegrees: function(MotionSample, SwayingWayingMotionProfile): number
        secondaryMotion: function(MotionSample, SwayingWayingMotionProfile, number): number, number
        secondaryAnimationTimes: function(number, number, number, MotionSettings): number, number
        secondaryGeometry: function(SwayingWayingMotionProfile, number): MotionGeometry
        curveLeanDegrees: function(number): number
        animationTime: function(MotionSample, MotionSettings): number
        animationTimes: function(MotionSample, MotionSettings, MotionGeometry): number, number, number
        neutralAnimationTimes: function(): number, number, number
        prepareWaves: function(CarriageState, number, number)
        sectionWaves: function(CarriageState, integer)
    end

    record TrackResponse
        speedLimitFactor: function(number): number
        shortWeightForFactor: function(number): number
        combinedFactor: function(number, number): number
        applyInfluence: function(number, number, number): number, number
        factor: function(Transformator.LandVehicleScriptingApi, integer, integer, number, number): number
        response: function(Transformator.LandVehicleScriptingApi, integer, integer, number, number): number, number
    end

    record VehicleResponse
        comfortFactor: function(any, boolean): number
        maintenanceFactor: function(any): number
        scaleFromNeutral: function(number, number): number
    end

    record ResourcePaths
        trfCandidates: function(string, string): {string}
        scriptCandidates: function(string, string): {string}, {string}
    end

    record ModelModifier
        configure: function(AllModParams | nil)
        modify: function(string, any, Config, ?boolean, ?ModelLoadOptions): any
    end

    record Origin
        update: UpdateFn | nil
        capture: any
        particles: UpdateParticleSystemFn | nil
        particlesCapture: any
        getEmittableModels: GetEmittableModelsFn | nil
        getEmittableModelsCapture: any
        computeEmittedModels: ComputeEmittedModelsFn | nil
        computeEmittedModelsCapture: any
    end

    record OriginLoader
        get: function(string, string, SwayingWayingCarrier): Origin | nil
    end

    record TransformatorScript
        updateFn: UpdateFn
        updateParticleSystemFn: UpdateParticleSystemFn
        getEmittableModelsFn: GetEmittableModelsFn | nil
        computeEmittedModelsFn: ComputeEmittedModelsFn | nil
    end

    record TransformatorConfigFactory
        create: function(string): any
    end
end
